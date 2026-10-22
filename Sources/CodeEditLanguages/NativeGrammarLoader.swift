import Foundation
import CryptoKit
import Darwin
import TreeSitter
import os

private let nativeGrammarLogger = Logger(subsystem: "com.codeedit.CodeEditLanguages", category: "NativeGrammarLoader")

/// A native tree-sitter grammar shipped inside an extension pack.
public struct NativeGrammarSpec: Hashable, Sendable {
    /// Absolute path of the `.dylib` inside the pack.
    public let path: URL
    /// Exported `tree_sitter_*` entry point.
    public let symbol: String
    /// SHA-256 the pack pinned, when it declared one.
    public let expectedSHA256: String?
    /// The pack root the dylib must stay inside.
    public let packRoot: URL

    public init(path: URL, symbol: String, expectedSHA256: String? = nil, packRoot: URL) {
        self.path = path
        self.symbol = symbol
        self.expectedSHA256 = expectedSHA256
        self.packRoot = packRoot
    }
}

/// Why a native grammar could not be loaded. Codes are stable so the UI can group them.
public enum NativeGrammarLoadError: Error, Equatable, Sendable {
    case outsidePackRoot
    case notARegularFile
    case temporaryLocation
    case unreadable
    case unsupportedArchitecture
    case conflictingRuntimeDependency(String)
    case hashMismatch(expected: String, actual: String)
    case openFailed(String)
    case symbolMissing(String)
    case incompatibleABI(found: UInt32, supported: ClosedRange<UInt32>)
    case incompleteExternalScanner(String)

    public var message: String {
        switch self {
        case .outsidePackRoot:
            return "The grammar file is outside the extension's directory."
        case .notARegularFile:
            return "The grammar path is not a regular file."
        case .temporaryLocation:
            return "The grammar was not loaded from an installed location."
        case .unreadable:
            return "The grammar file could not be read."
        case .unsupportedArchitecture:
            return "The grammar does not contain a slice for this Mac's architecture."
        case .conflictingRuntimeDependency(let name):
            return "The grammar links against a different tree-sitter runtime (\(name))."
        case .hashMismatch(let expected, let actual):
            return "The grammar changed since it was approved (expected \(expected.prefix(12))…, found \(actual.prefix(12))…)."
        case .openFailed(let detail):
            return "The grammar could not be loaded: \(detail)"
        case .symbolMissing(let symbol):
            return "The grammar does not export \(symbol)."
        case .incompatibleABI(let found, let supported):
            return "The grammar uses tree-sitter ABI \(found); this build supports \(supported.lowerBound)–\(supported.upperBound)."
        case .incompleteExternalScanner(let symbol):
            return "The grammar's external scanner is incomplete: \(symbol) is missing."
        }
    }
}

/// Loads native grammars contributed by trusted extension packs.
///
/// Loading is lazy, happens once per grammar, and never unloads: an editor session may still hold a
/// `Language` built from the handle. Failures are cached per path so the Extensions UI can report
/// them without retrying a doomed `dlopen`.
///
/// PERF: handles are retained for the process lifetime (unloading while a parser may still hold the
/// `TSLanguage` is undefined). The cache is one entry per trusted grammar, not per document. Hashing
/// reads the whole dylib once per load; do not re-hash on highlight/edit.
public final class NativeGrammarLoader: @unchecked Sendable {
    public static let shared = NativeGrammarLoader()

    private struct CacheKey: Hashable {
        let path: String
        let symbol: String
        let expectedHash: String
    }

    private struct Entry {
        let handle: UnsafeMutableRawPointer
        let language: OpaquePointer
        let path: String
        let hash: String
    }

    private let lock = NSLock()
    private var entries: [CacheKey: Entry] = [:]
    private var hashesByPath: [String: String] = [:]
    private var failures: [String: NativeGrammarLoadError] = [:]

    private init() {}

    /// The tree-sitter language exported by `spec`, loading the dylib on first use.
    public func language(for spec: NativeGrammarSpec) throws -> OpaquePointer {
        let canonicalPath = spec.path.resolvingSymlinksInPath().standardizedFileURL.path
        let key = CacheKey(path: canonicalPath, symbol: spec.symbol, expectedHash: spec.expectedSHA256 ?? "")

        lock.lock()
        defer { lock.unlock() }

        if let entry = entries[key] {
            return entry.language
        }
        if let failure = failures[canonicalPath] {
            throw failure
        }

        do {
            let entry = try load(spec, canonicalPath: canonicalPath)
            entries[key] = entry
            hashesByPath[canonicalPath] = entry.hash
            return entry.language
        } catch let error as NativeGrammarLoadError {
            failures[canonicalPath] = error
            nativeGrammarLogger.error(
                "Native grammar \(canonicalPath, privacy: .public) failed: \(error.message, privacy: .public)"
            )
            throw error
        }
    }

    /// The recorded failure for a grammar path, for the Extensions UI.
    public func failure(for path: URL) -> NativeGrammarLoadError? {
        let canonicalPath = path.resolvingSymlinksInPath().standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        return failures[canonicalPath]
    }

    /// The SHA-256 of a grammar that loaded successfully, for consent checks and display.
    public func loadedHash(for path: URL) -> String? {
        let canonicalPath = path.resolvingSymlinksInPath().standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        return hashesByPath[canonicalPath]
    }

    /// Drops recorded failures so a re-consented pack is attempted again. Loaded handles stay.
    public func resetFailures() {
        lock.lock()
        failures.removeAll()
        lock.unlock()
    }

    // MARK: - Load pipeline

    private func load(_ spec: NativeGrammarSpec, canonicalPath: String) throws -> Entry {
        try validate(spec, canonicalPath: canonicalPath)

        guard let data = try? Data(contentsOf: spec.path) else { throw NativeGrammarLoadError.unreadable }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let expected = spec.expectedSHA256, expected != hash {
            throw NativeGrammarLoadError.hashMismatch(expected: expected, actual: hash)
        }

        let slices = MachOSlices(data: data)
        guard try slices.containsCurrentArchitecture() else {
            throw NativeGrammarLoadError.unsupportedArchitecture
        }
        if let dependency = try slices.treeSitterRuntimeDependency() {
            throw NativeGrammarLoadError.conflictingRuntimeDependency(dependency)
        }

        guard let handle = dlopen(canonicalPath, RTLD_NOW | RTLD_LOCAL) else {
            throw NativeGrammarLoadError.openFailed(String(cString: dlerror()))
        }
        guard let symbol = dlsym(handle, spec.symbol) else {
            throw NativeGrammarLoadError.symbolMissing(spec.symbol)
        }

        let entryPoint = unsafeBitCast(symbol, to: (@convention(c) () -> OpaquePointer?).self)
        guard let language = entryPoint() else {
            throw NativeGrammarLoadError.symbolMissing(spec.symbol)
        }

        let supported = UInt32(TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION)...UInt32(TREE_SITTER_LANGUAGE_VERSION)
        let abi = ts_language_abi_version(language)
        guard supported.contains(abi) else {
            throw NativeGrammarLoadError.incompatibleABI(found: abi, supported: supported)
        }
        try validateExternalScanner(handle: handle, symbol: spec.symbol)

        return Entry(handle: handle, language: language, path: canonicalPath, hash: hash)
    }

    private func validate(_ spec: NativeGrammarSpec, canonicalPath: String) throws {
        let rootPath = spec.packRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard canonicalPath != rootPath, canonicalPath.hasPrefix(rootPath + "/") else {
            throw NativeGrammarLoadError.outsidePackRoot
        }

        let temporaryPath = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .standardizedFileURL.path
        guard !canonicalPath.hasPrefix(temporaryPath + "/") else {
            throw NativeGrammarLoadError.temporaryLocation
        }

        let values = try? spec.path.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { throw NativeGrammarLoadError.notARegularFile }
    }

    private func validateExternalScanner(handle: UnsafeMutableRawPointer, symbol: String) throws {
        let prefix = symbol + "_external_scanner_"
        guard dlsym(handle, prefix + "create") != nil else { return }
        for suffix in ["destroy", "scan"] where dlsym(handle, prefix + suffix) == nil {
            throw NativeGrammarLoadError.incompleteExternalScanner(prefix + suffix)
        }
    }
}

// MARK: - Mach-O inspection

/// Minimal Mach-O reader: architecture slices and tree-sitter runtime dependencies.
private struct MachOSlices {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    private static let cpuTypeX86_64: UInt32 = 0x0100_0007
    private static let cpuTypeARM64: UInt32 = 0x0100_000C

    private static var hostCPUType: UInt32 {
        #if arch(arm64)
        return cpuTypeARM64
        #else
        return cpuTypeX86_64
        #endif
    }

    func containsCurrentArchitecture() throws -> Bool {
        guard data.count >= 8 else { return false }

        if data.readUInt32BE(at: 0) == 0xCAFE_BABE {
            let count = min(Int(data.readUInt32BE(at: 4)), Self.maximumFatArchitectures)
            for index in 0..<count {
                let offset = 8 + index * 20
                guard offset + 4 <= data.count else { return false }
                if data.readUInt32BE(at: offset) == Self.hostCPUType { return true }
            }
            return false
        }

        let magic = data.readUInt32LE(at: 0)
        guard magic == 0xFEED_FACE || magic == 0xFEED_FACF else { return false }
        return data.readUInt32LE(at: 4) == Self.hostCPUType
    }

    /// The first linked library that looks like a tree-sitter runtime, if any.
    func treeSitterRuntimeDependency() throws -> String? {
        if let sliceOffset = currentArchitectureSliceOffset() {
            return loadCommandTreeSitterDependency(at: sliceOffset)
        }
        return loadCommandTreeSitterDependency(at: 0)
    }

    private static let maximumFatArchitectures = 16
    private static let maximumLoadCommands = 512

    /// Byte offset of this Mac's slice inside a fat binary, or `nil` for a thin image.
    private func currentArchitectureSliceOffset() -> Int? {
        guard data.count >= 8, data.readUInt32BE(at: 0) == 0xCAFE_BABE else { return nil }
        let count = min(Int(data.readUInt32BE(at: 4)), Self.maximumFatArchitectures)
        for index in 0..<count {
            let offset = 8 + index * 20
            guard offset + 16 <= data.count else { return nil }
            if data.readUInt32BE(at: offset) == Self.hostCPUType {
                return Int(data.readUInt32BE(at: offset + 8))
            }
        }
        return nil
    }

    private func loadCommandTreeSitterDependency(at sliceOffset: Int) -> String? {
        guard sliceOffset >= 0, sliceOffset + 32 <= data.count else { return nil }
        guard data.readUInt32LE(at: sliceOffset) == 0xFEED_FACF else { return nil }

        let commandCount = min(Int(data.readUInt32LE(at: sliceOffset + 16)), Self.maximumLoadCommands)
        var offset = sliceOffset + 32
        for _ in 0..<commandCount {
            guard offset + 8 <= data.count else { return nil }
            let command = data.readUInt32LE(at: offset)
            let size = Int(data.readUInt32LE(at: offset + 4))
            guard size >= 8, offset + size <= data.count else { return nil }

            let kind = command & 0x7FFF_FFFF
            if [0x0C, 0x18, 0x1F].contains(kind), size >= 24 {
                let nameOffset = Int(data.readUInt32LE(at: offset + 8))
                if let name = data.string(at: offset + nameOffset, endingBefore: offset + size),
                   name.lowercased().contains("tree-sitter") {
                    return name
                }
            }
            offset += size
        }
        return nil
    }
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[startIndex + offset]) << 24
            | UInt32(self[startIndex + offset + 1]) << 16
            | UInt32(self[startIndex + offset + 2]) << 8
            | UInt32(self[startIndex + offset + 3])
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[startIndex + offset])
            | UInt32(self[startIndex + offset + 1]) << 8
            | UInt32(self[startIndex + offset + 2]) << 16
            | UInt32(self[startIndex + offset + 3]) << 24
    }

    func string(at offset: Int, endingBefore limit: Int) -> String? {
        guard offset >= 0, offset < limit, limit <= count else { return nil }
        var end = offset
        while end < limit, self[startIndex + end] != 0 { end += 1 }
        return String(data: self[(startIndex + offset)..<(startIndex + end)], encoding: .utf8)
    }
}
