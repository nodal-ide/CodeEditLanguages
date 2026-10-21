//
//  CodeLanguage+Lookup.swift
//  CodeEditLanguages
//

import Foundation

public extension CodeLanguage {
    /// Returns the language with the given identifier.
    static func languageForID(_ id: LanguageID) -> CodeLanguage? {
        LanguageCatalog.builtIn.language(for: id)
    }

    /// Returns the language registered for the given file extension.
    static func languageForExtension(_ fileExtension: String) -> CodeLanguage? {
        LanguageCatalog.builtIn.language(forFileExtension: fileExtension)
    }

    /// Returns the language registered for an exact file name, such as `Dockerfile`.
    static func languageForFileName(_ fileName: String) -> CodeLanguage? {
        LanguageCatalog.builtIn.language(forFileName: fileName)
    }

    /// Returns the language for a shebang, modeline, or hover language identifier.
    static func languageForIdentifier(_ identifier: String) -> CodeLanguage? {
        LanguageCatalog.builtIn.language(forIdentifier: identifier)
    }
}
