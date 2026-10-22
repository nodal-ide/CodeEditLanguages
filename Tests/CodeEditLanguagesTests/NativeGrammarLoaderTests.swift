import Foundation
import CryptoKit
import XCTest
@testable import CodeEditLanguages

/// Exercises ``NativeGrammarLoader`` against synthetic dylibs built with clang.
///
/// Fixtures live outside the system temp directory because the loader intentionally refuses to load
/// grammars from a temporary (staging) location.
final class NativeGrammarLoaderTests: XCTestCase {
    private var packRoot: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        packRoot = base
            .appendingPathComponent("CodeEditNativeGrammarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: packRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: packRoot)
        NativeGrammarLoader.shared.resetFailures()
    }

    // MARK: - Fixtures

    private static let validGrammar = """
    typedef struct TSLanguage TSLanguage;
    static unsigned fixture[8] = {15, 0, 0, 0, 0, 0, 0, 0};
    const TSLanguage *tree_sitter_fixture(void) { return (const TSLanguage *)fixture; }
    """

    @discardableResult
    private func compile(_ source: String, to fileName: String, arch: String? = nil,
                         extra: [String] = []) throws -> URL {
        let compiler = "/usr/bin/clang"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: compiler), "clang is unavailable")

        let sourceURL = packRoot.appendingPathComponent("\(fileName).c")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        let outputURL = packRoot.appendingPathComponent(fileName)

        var arguments: [String] = []
        if let arch { arguments.append(contentsOf: ["-arch", arch]) }
        arguments.append(contentsOf: ["-dynamiclib", "-o", outputURL.path, sourceURL.path])
        arguments.append(contentsOf: extra)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: compiler)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw XCTSkip("clang could not build \(fileName): \(detail)")
        }
        return outputURL
    }

    private func spec(
        path: URL, symbol: String = "tree_sitter_fixture", sha256: String? = nil
    ) -> NativeGrammarSpec {
        NativeGrammarSpec(path: path, symbol: symbol, expectedSHA256: sha256, packRoot: packRoot)
    }

    private func assertFails(_ spec: NativeGrammarSpec, with expected: NativeGrammarLoadError,
                            _ message: String = "", line: UInt = #line) {
        do {
            _ = try NativeGrammarLoader.shared.language(for: spec)
            XCTFail("Expected \(expected) \(message)", line: line)
        } catch let error as NativeGrammarLoadError {
            XCTAssertEqual(error, expected, message, line: line)
        } catch {
            XCTFail("Unexpected error \(error) \(message)", line: line)
        }
    }

    // MARK: - Tests

    func testLoadsUniversalBinaryContainingHostArchitecture() throws {
        let library = try compile(
            Self.validGrammar,
            to: "libtree-sitter-universal.dylib",
            extra: ["-arch", "arm64", "-arch", "x86_64"]
        )
        XCTAssertNoThrow(try NativeGrammarLoader.shared.language(for: spec(path: library)))
    }

    func testLoadsValidNativeGrammar() throws {
        let library = try compile(Self.validGrammar, to: "libtree-sitter-fixture.dylib")
        let pointer = try NativeGrammarLoader.shared.language(for: spec(path: library))
        XCTAssertNotEqual(pointer, OpaquePointer(bitPattern: 0))
        XCTAssertNotNil(NativeGrammarLoader.shared.loadedHash(for: library))

        let language = CodeLanguage(
            id: LanguageID(rawValue: "fixture"),
            tsName: "fixture",
            extensions: ["fixture"],
            lineCommentString: "//",
            rangeCommentStrings: ("/*", "*/"),
            grammar: GrammarReference(native: spec(path: library), identifier: "fixture")
        )
        XCTAssertNotNil(language.language)
    }

    func testRecordsFailureForTheUIConsumer() throws {
        let missing = packRoot.appendingPathComponent("absent.dylib")
        assertFails(spec(path: missing), with: .notARegularFile)
        XCTAssertEqual(NativeGrammarLoader.shared.failure(for: missing), .notARegularFile)
    }

    func testRejectsUnreadableSymbol() throws {
        let library = try compile(Self.validGrammar, to: "libtree-sitter-other.dylib")
        assertFails(spec(path: library, symbol: "tree_sitter_other"), with: .symbolMissing("tree_sitter_other"))
    }

    func testRejectsNullGrammarPointer() throws {
        let source = """
        typedef struct TSLanguage TSLanguage;
        const TSLanguage *tree_sitter_fixture(void) { return 0; }
        """
        let library = try compile(source, to: "libtree-sitter-null.dylib")
        assertFails(spec(path: library), with: .symbolMissing("tree_sitter_fixture"))
    }

    func testRejectsIncompatibleABI() throws {
        let source = """
        typedef struct TSLanguage TSLanguage;
        static unsigned fixture[8] = {99, 0, 0, 0, 0, 0, 0, 0};
        const TSLanguage *tree_sitter_fixture(void) { return (const TSLanguage *)fixture; }
        """
        let library = try compile(source, to: "libtree-sitter-abi.dylib")
        do {
            _ = try NativeGrammarLoader.shared.language(for: spec(path: library))
            XCTFail("Expected an ABI rejection")
        } catch let error as NativeGrammarLoadError {
            guard case .incompatibleABI(let found, _) = error else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(found, 99)
        }
    }

    func testRejectsIncompleteExternalScanner() throws {
        let source = Self.validGrammar + """

        void *tree_sitter_fixture_external_scanner_create(void) { return 0; }
        """
        let library = try compile(source, to: "libtree-sitter-scanner.dylib")
        assertFails(
            spec(path: library),
            with: .incompleteExternalScanner("tree_sitter_fixture_external_scanner_destroy")
        )
    }

    func testRejectsHashMismatch() throws {
        let library = try compile(Self.validGrammar, to: "libtree-sitter-hash.dylib")
        let wrong = String(repeating: "a", count: 64)
        assertFails(
            spec(path: library, sha256: wrong),
            with: .hashMismatch(expected: wrong, actual: try sha256(of: library))
        )
    }

    func testAcceptsMatchingHash() throws {
        let library = try compile(Self.validGrammar, to: "libtree-sitter-pinned.dylib")
        let pinned = try sha256(of: library)
        XCTAssertNoThrow(try NativeGrammarLoader.shared.language(for: spec(path: library, sha256: pinned)))
    }

    func testRejectsPathOutsidePackRoot() throws {
        let outside = packRoot.appendingPathComponent("..").appendingPathComponent("escape.dylib")
        assertFails(spec(path: outside), with: .outsidePackRoot)
    }

    func testRejectsTemporaryLocation() throws {
        let library = try compile(Self.validGrammar, to: "libtree-sitter-temp.dylib")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ce-native-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let staged = temporaryDirectory.appendingPathComponent("libtree-sitter-staged.dylib")
        try FileManager.default.copyItem(at: library, to: staged)
        let stagedSpec = NativeGrammarSpec(
            path: staged, symbol: "tree_sitter_fixture", packRoot: temporaryDirectory
        )
        assertFails(stagedSpec, with: .temporaryLocation)
    }

    func testRejectsWrongArchitecture() throws {
        let other = try Self.otherArchitecture()
        let library = try compile(Self.validGrammar, to: "libtree-sitter-foreign.dylib", arch: other)
        assertFails(spec(path: library), with: .unsupportedArchitecture)
    }

    func testRejectsTreeSitterRuntimeDependency() throws {
        let fake = try compile(
            "int fake_dep(void) { return 0; }", to: "libtree-sitter-fake.dylib"
        )
        let source = Self.validGrammar + """

        extern int fake_dep(void);
        int uses_dep(void) { return fake_dep(); }
        """
        let library = try compile(
            source, to: "libtree-sitter-linked.dylib",
            extra: ["-L", packRoot.path, "-ltree-sitter-fake", "-Wl,-rpath,\(packRoot.path)"]
        )
        XCTAssertNotNil(fake)
        do {
            _ = try NativeGrammarLoader.shared.language(for: spec(path: library))
            XCTFail("Expected a runtime dependency rejection")
        } catch let error as NativeGrammarLoadError {
            guard case .conflictingRuntimeDependency = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    // MARK: - Helpers

    private static func otherArchitecture() throws -> String {
        #if arch(arm64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }

    private func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
