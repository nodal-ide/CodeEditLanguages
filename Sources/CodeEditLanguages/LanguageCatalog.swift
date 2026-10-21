import Foundation
import CryptoKit
import SwiftTreeSitter

/// Identifies the grammar backing a language definition.
public struct GrammarReference: Hashable, Sendable {
    public let identifier: String
    public let builtInLanguage: TreeSitterLanguage?

    public init(identifier: String, builtInLanguage: TreeSitterLanguage? = nil) {
        self.identifier = identifier
        self.builtInLanguage = builtInLanguage
    }

    public init(_ language: TreeSitterLanguage) {
        self.init(identifier: language.rawValue, builtInLanguage: language)
    }
}

/// The query files that make up a language's syntax definition.
public struct LanguageQuerySet: Hashable {
    public let highlights: URL
    public let parentHighlights: URL?
    public let additionalHighlights: [URL]
    public let injections: URL?

    public init(
        highlights: URL,
        parentHighlights: URL? = nil,
        additionalHighlights: [URL] = [],
        injections: URL? = nil
    ) {
        self.highlights = highlights
        self.parentHighlights = parentHighlights
        self.additionalHighlights = additionalHighlights
        self.injections = injections
    }

    public var sourceURLs: [URL] {
        [highlights] + additionalHighlights + [parentHighlights, injections].compactMap { $0 }
    }
}

/// A content-derived version for a language's grammar, queries, and metadata.
public struct LanguageFingerprint: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Metadata needed to register a language without tying the catalog to a particular grammar distribution.
public struct LanguageDefinition {
    public let id: LanguageID
    public let displayName: String
    public let grammar: GrammarReference
    public let querySet: LanguageQuerySet?
    public let extensions: Set<String>
    public let additionalIdentifiers: Set<String>

    public init(
        id: LanguageID,
        displayName: String,
        grammar: GrammarReference,
        querySet: LanguageQuerySet?,
        extensions: Set<String>,
        additionalIdentifiers: Set<String> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.grammar = grammar
        self.querySet = querySet
        self.extensions = extensions
        self.additionalIdentifiers = additionalIdentifiers
    }
}

/// An immutable lookup table for built-in and contributed languages.
public struct LanguageCatalog {
    public static let builtIn = LanguageCatalog(languages: CodeLanguage.allLanguages + [.default])

    public let languages: [CodeLanguage]

    private let byID: [LanguageID: CodeLanguage]
    private let byExtension: [String: CodeLanguage]
    private let byFileName: [String: CodeLanguage]
    private let byIdentifier: [String: CodeLanguage]

    public init(languages: [CodeLanguage]) {
        self.languages = languages

        var byID: [LanguageID: CodeLanguage] = [:]
        var byExtension: [String: CodeLanguage] = [:]
        var byFileName: [String: CodeLanguage] = [:]
        var byIdentifier: [String: CodeLanguage] = [:]

        for language in languages where byID[language.id] == nil {
            byID[language.id] = language
        }
        for language in languages {
            for fileExtension in language.extensions {
                let key = fileExtension.lowercased()
                if byExtension[key] == nil {
                    byExtension[key] = language
                }
                if byFileName[fileExtension] == nil {
                    byFileName[fileExtension] = language
                }
            }
        }
        for language in languages {
            byIdentifier[language.id.rawValue.lowercased()] = language
        }
        for language in languages {
            let key = language.tsName.lowercased()
            if byIdentifier[key] == nil {
                byIdentifier[key] = language
            }
        }
        for language in languages {
            for identifier in language.extensions.union(language.additionalIdentifiers) {
                let key = identifier.lowercased()
                if byIdentifier[key] == nil {
                    byIdentifier[key] = language
                }
            }
        }

        self.byID = byID
        self.byExtension = byExtension
        self.byFileName = byFileName
        self.byIdentifier = byIdentifier
    }

    public func language(for id: LanguageID) -> CodeLanguage? {
        byID[id]
    }

    public func language(forFileExtension fileExtension: String) -> CodeLanguage? {
        byExtension[fileExtension.lowercased()]
    }

    public func language(forFileName fileName: String) -> CodeLanguage? {
        byFileName[fileName]
    }

    public func language(forIdentifier identifier: String) -> CodeLanguage? {
        let normalized = identifier.lowercased()
        if let alias = Self.identifierAliases[normalized] {
            return byID[alias]
        }
        return byIdentifier[normalized]
    }

    private static let identifierAliases: [String: LanguageID] = [
        "c#": .cSharp,
        "csharp": .cSharp,
        "c-sharp": .cSharp,
        "c++": .cpp,
        "js": .javascript,
        "ts": .typescript,
        "py": .python,
        "rb": .ruby,
        "sh": .bash,
        "shell": .bash,
        "yml": .yaml,
        "md": .markdown,
        "markdown_inline": .markdownInline,
        "markdown-inline": .markdownInline,
        "objective-c": .objc,
        "objectivec": .objc,
        "gomod": .goMod,
        "go-mod": .goMod,
        "ocaml-interface": .ocamlInterface,
        "ocamlinterface": .ocamlInterface
    ]
}

final class LanguageFingerprintCache {
    static let shared = LanguageFingerprintCache()

    private struct CacheKey: Hashable {
        let id: LanguageID
        let tsName: String
        let grammar: String
        let queryFiles: [String]
    }

    private let lock = NSLock()
    private var values: [CacheKey: LanguageFingerprint] = [:]

    func fingerprint(for language: CodeLanguage) -> LanguageFingerprint {
        let queryFiles = (language.querySet?.sourceURLs ?? []).map { url -> String in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int ?? 0
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(url.path):\(size):\(modified)"
        }
        let key = CacheKey(
            id: language.id,
            tsName: language.tsName,
            grammar: language.grammar.identifier,
            queryFiles: queryFiles
        )

        lock.lock()
        if let value = values[key] {
            lock.unlock()
            return value
        }
        lock.unlock()

        var hasher = SHA256()
        hasher.update(data: Data(language.id.rawValue.utf8))
        hasher.update(data: Data(language.tsName.utf8))
        hasher.update(data: Data(language.grammar.identifier.utf8))
        hasher.update(data: Data(String(Language.version).utf8))
        for extensionName in language.extensions.sorted() {
            hasher.update(data: Data(extensionName.utf8))
        }
        if let querySet = language.querySet {
            for url in querySet.sourceURLs {
                hasher.update(data: Data(url.path.utf8))
                if let data = try? Data(contentsOf: url) {
                    hasher.update(data: data)
                }
            }
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let fingerprint = LanguageFingerprint(rawValue: digest)

        lock.lock()
        values[key] = fingerprint
        lock.unlock()
        return fingerprint
    }
}
