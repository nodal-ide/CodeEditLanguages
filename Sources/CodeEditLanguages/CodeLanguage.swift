//
//  CodeLanguage.swift
//  CodeEditTextView/CodeLanguage
//
//  Created by Lukas Pistrol on 25.05.22.
//

import Foundation
import TreeSitter
import SwiftTreeSitter
import CodeLanguages_Container
import TreeSitterDotenv
import TreeSitterGitignore
import TreeSitterApacheconf
import RegexBuilder

/// A structure holding metadata for code languages
public struct CodeLanguage {
    public init(
        id: LanguageID,
        tsName: String,
        extensions: Set<String>,
        lineCommentString: String,
        rangeCommentStrings: (String, String),
        documentationCommentStrings: Set<DocumentationComments> = [],
        grammar: GrammarReference? = nil,
        parentURL: URL? = nil,
        highlights: Set<String>? = nil,
        additionalIdentifiers: Set<String> = [],
        resourceURL: URL? = nil,
        queryURLs: [String: URL] = [:],
        firstLinePatterns: [String] = []
    ) {
        self.id = id
        self.tsName = tsName
        self.extensions = extensions
        self.lineCommentString = lineCommentString
        self.rangeCommentStrings = rangeCommentStrings
        self.documentationCommentStrings = documentationCommentStrings
        self.grammar = grammar ?? id.treeSitterLanguage.map { GrammarReference($0) }
            ?? GrammarReference(identifier: id.rawValue)
        self.parentQueryURLOverride = parentURL
        self.additionalHighlights = highlights
        self.additionalIdentifiers = additionalIdentifiers
        self.resourceURL = resourceURL ?? Bundle.module.resourceURL
        self.queryURLs = queryURLs
        self.firstLinePatterns = firstLinePatterns
    }

    /// The ID of the language
    public let id: LanguageID

    /// The grammar backing the language.
    public let grammar: GrammarReference

    /// The display name of the language
    public let tsName: String

    /// A set of file extensions for the language
    ///
    /// In special cases this can also be a file name
    /// (e.g `Dockerfile`, `Makefile`)
    public let extensions: Set<String>

    /// The leading string of a comment line
    public let lineCommentString: String

    /// The leading and trailing string of a multi-line comment
    public let rangeCommentStrings: (String, String)

    /// The leading (and trailing, if there is one) string of a documentation comment
    public let documentationCommentStrings: Set<DocumentationComments>

    /// The query URL of a language this language inherits from. (e.g.: C for C++)
    ///
    /// `nil` for contributed languages that declare the parent query in ``queryURLs``.
    public let parentQueryURLOverride: URL?

    /// Explicit query files, keyed by query name (`highlights`, `injections`, `folds`, …).
    ///
    /// Built-in languages resolve queries inside their bundle; contributed languages (for example
    /// extension syntax packs) ship their queries outside the bundle and list them here.
    public let queryURLs: [String: URL]

    /// Regular expressions matched against the first line of a document, in declaration order.
    ///
    /// This is the last detection tier, after file name, extension, shebang, and modeline.
    public let firstLinePatterns: [String]

    /// Additional highlight file names (e.g.: JSX for JavaScript)
    public let additionalHighlights: Set<String>?

    /// The query URL of a language this language inherits from. (e.g.: C for C++)
    public var parentQueryURL: URL? {
        queryURLs["parent"] ?? parentQueryURLOverride
    }

    /// The query URL for the language if available
    public var queryURL: URL? {
        queryURL()
    }

    /// The query files used for syntax highlighting.
    public var querySet: LanguageQuerySet? {
        guard let highlights = queryURL else { return nil }
        let additional = (additionalHighlights ?? [])
            .filter { $0 != "highlights" }
            .compactMap { queryURL(for: $0) }
            .sorted { $0.path < $1.path }
        return LanguageQuerySet(
            highlights: highlights,
            parentHighlights: parentQueryURL,
            additionalHighlights: additional,
            injections: queryURL(for: "injections")
        )
    }

    /// Metadata describing this language without exposing its grammar distribution.
    public var definition: LanguageDefinition {
        LanguageDefinition(
            id: id,
            displayName: tsName,
            grammar: grammar,
            querySet: querySet,
            extensions: extensions,
            additionalIdentifiers: additionalIdentifiers
        )
    }

    /// A content-derived version for grammar, query, and metadata invalidation.
    public var fingerprint: LanguageFingerprint {
        LanguageFingerprintCache.shared.fingerprint(for: self)
    }

    /// The bundle's resource URL
    internal var resourceURL: URL? = Bundle.module.resourceURL

    /// A set of aditional identifiers to use for things like shebang matching.
    public let additionalIdentifiers: Set<String>

    /// The tree-sitter language for the language if available
    public var language: Language? {
        guard let tsLanguage = tsLanguage else { return nil }
        return Language(language: tsLanguage)
    }

    internal var resourceDirectoryURL: URL? {
        guard let resourceURL else { return nil }
        let nestedURL = resourceURL.appendingPathComponent("Resources")
        return FileManager.default.fileExists(atPath: nestedURL.path) ? nestedURL : resourceURL
    }

    internal func queryURL(for highlights: String = "highlights") -> URL? {
        if let override = queryURLs[highlights] {
            return override
        }
        return resourceDirectoryURL?
            .appendingPathComponent("tree-sitter-\(tsName)/\(highlights).scm")
    }

    /// Gets the TSLanguage from `tree-sitter`
    ///
    /// Built-in languages map their ID to a statically linked grammar; contributed languages can
    /// reuse a built-in grammar (a query-only syntax pack) by declaring it in ``grammar``.
    private var tsLanguage: OpaquePointer? {
        guard let id = grammar.builtInLanguage ?? id.treeSitterLanguage else { return nil }
        switch id {
        case .agda:
            return tree_sitter_agda()
        case .apacheconf:
            return tree_sitter_apacheconf()
        case .bash:
            return tree_sitter_bash()
        case .c:
            return tree_sitter_c()
        case .cpp:
            return tree_sitter_cpp()
        case .cSharp:
            return tree_sitter_c_sharp()
        case .css:
            return tree_sitter_css()
        case .dart:
            return tree_sitter_dart()
        case .dockerfile:
            return tree_sitter_dockerfile()
        case .dotenv:
            return tree_sitter_dotenv()
        case .elixir:
            return tree_sitter_elixir()
        case .gitignore:
            return tree_sitter_gitignore()
        case .go:
            return tree_sitter_go()
        case .goMod:
            return tree_sitter_gomod()
        case .haskell:
            return tree_sitter_haskell()
        case .html:
            return tree_sitter_html()
        case .java:
            return tree_sitter_java()
        case .javascript:
            return tree_sitter_javascript()
        case .jsdoc:
            return tree_sitter_jsdoc()
        case .json:
            return tree_sitter_json()
        case .jsx:
            return tree_sitter_javascript()
        case .julia:
            return tree_sitter_julia()
        case .kotlin:
            return tree_sitter_kotlin()
        case .lua:
            return tree_sitter_lua()
        case .markdown:
            return tree_sitter_markdown()
        case .markdownInline:
            return tree_sitter_markdown_inline()
        case .objc:
            return tree_sitter_objc()
        case .ocaml:
            return tree_sitter_ocaml()
        case .ocamlInterface:
            return tree_sitter_ocaml_interface()
        case .perl:
            return tree_sitter_perl()
        case .php:
            return tree_sitter_php()
        case .python:
            return tree_sitter_python()
        case .regex:
            return tree_sitter_regex()
        case .ruby:
            return tree_sitter_ruby()
        case .rust:
            return tree_sitter_rust()
        case .scala:
            return tree_sitter_scala()
        case .sql:
            return tree_sitter_sql()
        case .swift:
            return tree_sitter_swift()
        case .toml:
            return tree_sitter_toml()
        case .tsx:
            return tree_sitter_tsx()
        case .typescript:
            return tree_sitter_typescript()
        case .verilog:
            return tree_sitter_verilog()
        case .yaml:
            return tree_sitter_yaml()
        case .zig:
            return tree_sitter_zig()
        case .plainText:
            return nil
        }
    }
}

extension CodeLanguage: Hashable {
    public static func == (lhs: CodeLanguage, rhs: CodeLanguage) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public enum DocumentationComments: Hashable {
    public static func == (lhs: DocumentationComments, rhs: DocumentationComments) -> Bool {
        switch lhs {
        case .single(let lhsString):
            switch rhs {
            case .single(let rhsString):
                return lhsString == rhsString
            case .pair:
                return false
            }
        case .pair(let lhsPair):
            switch rhs {
            case .single:
                return false
            case .pair(let rhsPair):
                return lhsPair.0 == rhsPair.0 && lhsPair.1 == rhsPair.1
            }
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .single(let string):
            hasher.combine(string)
        case .pair(let pair):
            hasher.combine(pair.0)
            hasher.combine(pair.1)
        }
    }

    case single(String)
    case pair((String, String))
}
