//
//  CodeLanguage+QueryCompilation.swift
//  CodeEditLanguages
//
//  Compiles a language's query files, so extension packs can be checked where the grammars live.
//

import Foundation
import SwiftTreeSitter

/// A failure to compile a query for a language.
public enum QueryCompilationError: Error {
    /// The language has no grammar (nothing to compile the query against).
    case noGrammar
}

public extension CodeLanguage {
    /// Compiles a query file against this language's grammar.
    ///
    /// Used by the extension loader to reject a malformed syntax pack with an actionable error,
    /// instead of letting highlighting fail silently the first time such a document is opened.
    ///
    /// - Parameter url: The query file to compile.
    /// - Returns: The capture names the query uses, in query order.
    /// - Throws: The tree-sitter query error when the query is malformed, or
    ///   ``QueryCompilationError/noGrammar`` when this language has no grammar.
    func compileQuery(at url: URL) throws -> [String] {
        guard let language else { throw QueryCompilationError.noGrammar }
        let query = try language.query(contentsOf: url)
        return (0..<query.captureCount).compactMap { query.captureName(for: $0) }
    }
}
