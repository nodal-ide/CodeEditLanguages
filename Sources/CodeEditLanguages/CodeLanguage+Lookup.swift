//
//  CodeLanguage+Lookup.swift
//  CodeEditLanguages
//

import Foundation

public extension CodeLanguage {
    private static let languagesByID: [TreeSitterLanguage: CodeLanguage] = allLanguages.reduce(into: [:]) {
        $0[$1.id] = $1
    }

    private static let languagesByExtension: [String: CodeLanguage] = {
        var result: [String: CodeLanguage] = [:]
        for language in allLanguages {
            for fileExtension in language.extensions {
                let key = fileExtension.lowercased()
                if result[key] == nil {
                    result[key] = language
                }
            }
        }
        return result
    }()

    private static let languagesByFileName: [String: CodeLanguage] = {
        var result: [String: CodeLanguage] = [:]
        for language in allLanguages {
            for fileName in language.extensions where result[fileName] == nil {
                result[fileName] = language
            }
        }
        return result
    }()

    private static let languagesByIdentifier: [String: CodeLanguage] = {
        var result: [String: CodeLanguage] = [:]

        // Prefer canonical IDs so names shared by sibling grammars (for example
        // `typescript` and `tsx`) resolve to the language with that ID.
        for language in allLanguages {
            result[language.id.rawValue.lowercased()] = language
        }
        for language in allLanguages {
            let key = language.tsName.lowercased()
            if result[key] == nil {
                result[key] = language
            }
        }
        for language in allLanguages {
            for identifier in language.extensions.union(language.additionalIdentifiers) {
                let key = identifier.lowercased()
                if result[key] == nil {
                    result[key] = language
                }
            }
        }
        return result
    }()

    private static let identifierAliases: [String: TreeSitterLanguage] = [
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

    /// Returns the language with the given tree-sitter identifier.
    static func languageForID(_ id: TreeSitterLanguage) -> CodeLanguage? {
        languagesByID[id]
    }

    /// Returns the language registered for the given file extension.
    static func languageForExtension(_ fileExtension: String) -> CodeLanguage? {
        languagesByExtension[fileExtension.lowercased()]
    }

    /// Returns the language registered for an exact file name, such as `Dockerfile`.
    static func languageForFileName(_ fileName: String) -> CodeLanguage? {
        languagesByFileName[fileName]
    }

    /// Returns the language for a shebang, modeline, or hover language identifier.
    static func languageForIdentifier(_ identifier: String) -> CodeLanguage? {
        let normalized = identifier.lowercased()
        if let id = identifierAliases[normalized] {
            return languagesByID[id]
        }
        return languagesByIdentifier[normalized]
    }
}
