//
//  CodeLanguage+DetectLanguage.swift
//  CodeEditLanguages
//
//  Created by Khan Winter on 6/17/23.
//

import Foundation

public extension CodeLanguage {

    /// Gets the corresponding language for the given file URL, using the built-in catalog.
    ///
    /// Contributed languages are only visible to a workspace catalog; callers that know their catalog
    /// (the app, providers) should use ``LanguageCatalog/detectLanguage(url:prefix:suffix:)`` directly.
    /// - Returns: A language structure
    /// - Parameters:
    ///   - url: The URL to get the language for.
    ///   - prefixBuffer: The first few lines of the document.
    ///   - suffixBuffer: The last few lines of the document.
    static func detectLanguageFrom(
        url: URL,
        prefixBuffer: String? = nil,
        suffixBuffer: String? = nil
    ) -> CodeLanguage {
        LanguageCatalog.builtIn.detectLanguage(url: url, prefix: prefixBuffer, suffix: suffixBuffer)
    }
}
