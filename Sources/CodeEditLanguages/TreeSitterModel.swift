//
//  TreeSitterModel.swift
//  CodeEditTextView/CodeLanguage
//
//  Created by Lukas Pistrol on 25.05.22.
//

import Foundation
import SwiftTreeSitter

/// A singleton class to manage `tree-sitter` queries and keep them in memory.
public class TreeSitterModel {

    /// The singleton/shared instance of ``TreeSitterModel``.
    public static let shared: TreeSitterModel = .init()

    /// Get a query for a specific language.
    /// - Parameter language: The language to request the query for.
    /// - Returns: A Query if available. Returns `nil` for unsupported languages.
    public func query(for language: LanguageID, catalog: LanguageCatalog = .builtIn) -> Query? {
        guard let codeLanguage = catalog.language(for: language) else {
            return nil
        }
        let key = QueryCache.Key(language: codeLanguage.id, fingerprint: codeLanguage.fingerprint)
        if let cached = Self.queryCache.value(for: key) {
            return cached
        }
        guard let query = queryFor(codeLanguage) else {
            return nil
        }
        Self.queryCache.insert(query, for: key)
        return query
    }

    /// Compatibility overload for legacy built-in language references.
    public func query(for language: TreeSitterLanguage) -> Query? {
        query(for: language.languageID)
    }

    /// Query for `Bash` files.
    public var bashQuery: Query? {
        query(for: .bash)
    }

    /// Query for `C` files.
    public var cQuery: Query? {
        query(for: .c)
    }

    /// Query for `C++` files.
    public var cppQuery: Query? {
        query(for: .cpp)
    }

    /// Query for `C#` files.
    public var cSharpQuery: Query? {
        query(for: .cSharp)
    }

    /// Query for `CSS` files.
    public var cssQuery: Query? {
        query(for: .css)
    }

    /// Query for `Dart` files.
    public var dartQuery: Query? {
        query(for: .dart)
    }

    /// Query for `Dockerfile` files.
    public var dockerfileQuery: Query? {
        query(for: .dockerfile)
    }

    /// Query for `dotenv` files.
    public var dotenvQuery: Query? {
        query(for: .dotenv)
    }

    /// Query for `ApacheConf` files.
    public var apacheconfQuery: Query? {
        query(for: .apacheconf)
    }

    /// Query for `Git Ignore` files.
    public var gitignoreQuery: Query? {
        query(for: .gitignore)
    }

    /// Query for `Elixir` files.
    public var elixirQuery: Query? {
        query(for: .elixir)
    }

    /// Query for `Go` files.
    public var goQuery: Query? {
        query(for: .go)
    }

    /// Query for `GoMod` files.
    public var goModQuery: Query? {
        query(for: .goMod)
    }

    /// Query for `Haskell` files.
    public var haskellQuery: Query? {
        query(for: .haskell)
    }

    /// Query for `HTML` files.
    public var htmlQuery: Query? {
        query(for: .html)
    }

    /// Query for `Java` files.
    public var javaQuery: Query? {
        query(for: .java)
    }

    /// Query for `JavaScript` files.
    public var javascriptQuery: Query? {
        query(for: .javascript)
    }

    /// Query for `JSDoc` files.
    public var jsdocQuery: Query? {
        query(for: .jsdoc)
    }

    /// Query for `JSX` files.
    public var jsxQuery: Query? {
        query(for: .jsx)
    }

    /// Query for `JSON` files.
    public var jsonQuery: Query? {
        query(for: .json)
    }

    /// Query for `Kotlin` files.
    public var kotlinQuery: Query? {
        query(for: .kotlin)
    }

    /// Query for `Lua` files.
    public var luaQuery: Query? {
        query(for: .lua)
    }

    /// Query for `Markdown` files.
    public var markdownQuery: Query? {
        query(for: .markdown)
    }

    /// Query for `Markdown Inline` files.
    public var markdownInlineQuery: Query? {
        query(for: .markdownInline)
    }

    /// Query for `Objective C` files.
    public var objcQuery: Query? {
        query(for: .objc)
    }

    /// Query for `OCaml` files.
    public var ocamlQuery: Query? {
        query(for: .ocaml)
    }

    /// Query for `OCaml Interface` files.
    public var ocamlInterfaceQuery: Query? {
        query(for: .ocamlInterface)
    }

    /// Query for `PHP` files.
    public var phpQuery: Query? {
        query(for: .php)
    }

    /// Query for `Python` files.
    public var pythonQuery: Query? {
        query(for: .python)
    }

    /// Query for `Regex` files.
    public var regexQuery: Query? {
        query(for: .regex)
    }

    /// Query for `Ruby` files.
    public var rubyQuery: Query? {
        query(for: .ruby)
    }

    /// Query for `Rust` files.
    public var rustQuery: Query? {
        query(for: .rust)
    }

    /// Query for `Scala` files.
    public var scalaQuery: Query? {
        query(for: .scala)
    }

    /// Query for `SQL` files.
    public var sqlQuery: Query? {
        query(for: .sql)
    }

    /// Query for `Swift` files.
    public var swiftQuery: Query? {
        query(for: .swift)
    }

    /// Query for `TOML` files.
    public var tomlQuery: Query? {
        query(for: .toml)
    }

    /// Query for `TSX` files.
    public var tsxQuery: Query? {
        query(for: .tsx)
    }

    /// Query for `Typescript` files.
    public var typescriptQuery: Query? {
        query(for: .typescript)
    }

    /// Query for `YAML` files.
    public var yamlQuery: Query? {
        query(for: .yaml)
    }

    /// Query for `Zig` files.
    public var zigQuery: Query? {
        query(for: .zig)
    }

    private static let queryCache = QueryCache(limit: 64)

    private func queryFor(_ codeLanguage: CodeLanguage) -> Query? {
        // get the tree-sitter language and query url if available
        guard let language = codeLanguage.language,
              let url = codeLanguage.queryURL else { return nil }

        // 1. if the language depends on another language combine the query files
        // 2. if the language has additional query files combine them with the main one
        // 3. otherwise return the query file
        if let parentURL = codeLanguage.parentQueryURL,
           let data = combinedQueryData(for: [url, parentURL]) {
            return try? Query(language: language, data: data)
        } else if let additionalHighlights = codeLanguage.additionalHighlights {
            var addURLs = additionalHighlights.compactMap({ codeLanguage.queryURL(for: $0) })
            addURLs.append(url)
            guard let data = combinedQueryData(for: addURLs) else { return nil }
            return try? Query(language: language, data: data)
        } else {
            return try? language.query(contentsOf: url)
        }
    }

    private func combinedQueryData(for fileURLs: [URL]) -> Data? {
        let rawQuery = fileURLs.compactMap { try? String(contentsOf: $0) }.joined(separator: "\n")
        if !rawQuery.isEmpty {
            return rawQuery.data(using: .utf8)
        } else {
            return nil
        }
    }

    private init() {}
}

private final class QueryCache {
    struct Key: Hashable {
        let language: LanguageID
        let fingerprint: LanguageFingerprint
    }

    private let limit: Int
    private let lock = NSLock()
    private var values: [Key: Query] = [:]
    private var order: [Key] = []

    init(limit: Int) {
        self.limit = limit
    }

    func value(for key: Key) -> Query? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    func insert(_ query: Query, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = query
        touch(key)
        while order.count > limit {
            let removed = order.removeFirst()
            values[removed] = nil
        }
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}
