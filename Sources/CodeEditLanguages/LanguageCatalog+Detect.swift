//
//  LanguageCatalog+Detect.swift
//  CodeEditLanguages
//
//  Language detection driven by a ``LanguageCatalog``.
//
//  Detection is tiered and deterministic: exact file name, file extension, shebang, modeline, then
//  contributed first-line patterns. Within a tier the catalog's language order decides the winner
//  (built-ins first, then global extension packs, then workspace packs), so contributed languages
//  never shadow a built-in.
//

import Foundation
import RegexBuilder

public extension LanguageCatalog {
    /// Gets the corresponding language for the given file URL.
    ///
    /// - Parameters:
    ///   - url: The URL to get the language for.
    ///   - prefix: The first few lines of the document (used for shebang/modeline/first-line detection).
    ///   - suffix: The last few lines of the document (used for trailing modelines).
    /// - Returns: The detected language, or the plain-text default.
    func detectLanguage(url: URL, prefix: String? = nil, suffix: String? = nil) -> CodeLanguage {
        if let urlLanguage = detectLanguageUsingURL(url: url) {
            return urlLanguage
        } else if let prefix,
                  let shebangLanguage = detectLanguageUsingShebang(contents: prefix.lowercased()) {
            return shebangLanguage
        } else if let prefix,
                  let modelineLanguage = detectLanguageUsingModeline(
                    prefix: prefix.lowercased(),
                    suffix: suffix?.lowercased()
                  ) {
            return modelineLanguage
        } else if let prefix, let firstLineLanguage = detectLanguageUsingFirstLine(prefix) {
            return firstLineLanguage
        } else {
            return defaultLanguage
        }
    }

    /// Detects a file's language using the file url.
    private func detectLanguageUsingURL(url: URL) -> CodeLanguage? {
        let fileExtension = url.pathExtension.lowercased()
        if !fileExtension.isEmpty {
            return language(forFileExtension: fileExtension)
        }
        // Special file types without an extension (e.g., Makefile, Dockerfile).
        guard let fileName = url.pathComponents.last else { return nil }
        return language(forFileName: fileName)
    }

    /// Detects a language from the shebang of a file.
    ///
    /// Eg: `#!/usr/bin/env/python2.6` will detect the `python` code language, or
    /// `#! /usr/bin/env perl` will detect the `perl` code language.
    private func detectLanguageUsingShebang(contents: String) -> CodeLanguage? {
        var contents = String(contents.split(separator: "\n").first ?? "")
        // Make sure:
        // - First line is a shebang
        // - There are contents after the shebang
        // - There is a valid script component (eg: "swift" in "/usr/env/swift")
        guard
            contents.starts(with: "#!"),
            contents.trimmingCharacters(in: .whitespacesAndNewlines) != "#!",
            let result = contents
                .split(separator: "/", omittingEmptySubsequences: true)
                .last?
                .firstMatch(of: Regex { OneOrMore(.word) })
        else {
            return nil
        }

        var script = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // If script is "env" walk the string until we find a valid-looking script component
        if script == "env" {
            // If env is the end of the string, return
            guard result.endIndex != contents.endIndex else { return nil }

            let argumentRegex = Regex {
                ZeroOrMore(.whitespace)
                ChoiceOf {
                    One("-")
                    One("--")
                }
                ZeroOrMore(.word)
                ZeroOrMore(.whitespace)
            }
            let parameterRegex = Regex {
                OneOrMore(.word)
                One("=")
                OneOrMore(.word)
            }

            // Skip over any optional arguments or parameters (eg: -x or x=y) and make script the next valid string
            // https://www.gnu.org/software/coreutils/manual/html_node/env-invocation.html
            // Skip first shebang-path string
            contents.trimPrefix(Regex {
                OneOrMore("#!")
                ZeroOrMore(.whitespace)
                OneOrMore(.any, .reluctant)
                OneOrMore(.whitespace)
            })
            while !contents.isEmpty {
                if contents.prefixMatch(of: argumentRegex) != nil {
                    contents.trimPrefix(argumentRegex)
                } else if contents.prefixMatch(of: parameterRegex) != nil {
                    contents.trimPrefix(parameterRegex)
                } else {
                    break
                }
            }
            guard let newScript = contents.firstMatch(of: Regex { OneOrMore(.word) })?.output else {
                return nil
            }
            script = String(newScript)
        }

        return language(forIdentifier: script)
    }

    /// Detects modelines in either the beginning or end of a file.
    ///
    /// Examples of valid modelines:
    /// ```
    /// # vim: set ft=js ts=4 sw=4 et:
    /// # vim: ts=4:sw=4:et:ft=js
    /// -*- mode: js; indent-tabs-mode: nil; tab-width: 4 -*-
    /// code: language=javascript insertSpaces=true tabSize=4
    /// ```
    /// All of the above would resolve to `javascript`
    private func detectLanguageUsingModeline(prefix: String, suffix: String?) -> CodeLanguage? {
        func detectModeline(in string: String) -> CodeLanguage? {
            guard !string.isEmpty else { return nil }

            // Regex for detecting emacs modelines.
            let emacsLineRegex = Regex {
                "-*-"
                Capture {
                    #/.*/#
                }
                "-*-"
            }

            // Regex to find language parameters in a emacs modeline.
            let emacsLanguageRegex = Regex {
                "mode:"
                ZeroOrMore(.whitespace)
                Capture {
                    OneOrMore(.word)
                }
            }

            // Regex for detecting vim modelines.
            let vimLineRegex = Regex {
                ChoiceOf {
                    One("//")
                    One("/*")
                }
                OneOrMore(.whitespace)
                #/vim:.*/#
                Optionally(.newlineSequence)
            }

            // Regex to find language parameters in a vim modeline.
            let vimLanguageRegex = Regex {
                "ft="
                Capture {
                    OneOrMore(.word)
                }
            }

            if let emacsLine = string.firstMatch(of: emacsLineRegex)?.1,
               let emacsLanguage = emacsLine.firstMatch(of: emacsLanguageRegex)?.1 {
                return language(forIdentifier: String(emacsLanguage))
            } else if let vimLine = string.firstMatch(of: vimLineRegex)?.0,
                      let vimLanguage = vimLine.firstMatch(of: vimLanguageRegex)?.1 {
                return language(forIdentifier: String(vimLanguage))
            } else {
                return nil
            }
        }

        return detectModeline(in: prefix) ?? detectModeline(in: suffix ?? "")
    }

    /// Detects a contributed language from its declared first-line patterns.
    private func detectLanguageUsingFirstLine(_ prefix: String) -> CodeLanguage? {
        guard !firstLineMatchers.isEmpty else { return nil }
        let firstLine = String(prefix.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
        let range = NSRange(firstLine.startIndex..<firstLine.endIndex, in: firstLine)
        for matcher in firstLineMatchers where matcher.regex.firstMatch(in: firstLine, range: range) != nil {
            if let language = language(for: matcher.languageID) {
                return language
            }
        }
        return nil
    }

    /// The catalog's plain-text language, used when nothing else matches.
    private var defaultLanguage: CodeLanguage {
        language(for: .plainText) ?? .default
    }
}
