//
//  TreeSitterLanguage.swift
//  CodeEditTextView/CodeLanguage
//
//  Created by Lukas Pistrol on 25.05.22.
//

import Foundation

/// A collection of languages that are supported by `tree-sitter`
public enum TreeSitterLanguage: String {
    case agda
    case apacheconf
    case bash
    case c
    case cpp
    case cSharp
    case css
    case dart
    case dockerfile
    case dotenv
    case elixir
    case gitignore
    case go
    case goMod
    case haskell
    case html
    case java
    case javascript
    case jsdoc
    case json
    case jsx
    case julia
    case kotlin
    case lua
    case markdown
    case markdownInline
    case objc
    case ocaml
    case ocamlInterface
    case perl
    case php
    case python
    case regex
    case ruby
    case rust
    case scala
    case sql
    case swift
    case toml
    case tsx
    case typescript
    case verilog
    case yaml
    case zig
    case plainText
}

public extension TreeSitterLanguage {
    private static let injectionAliases: [String: TreeSitterLanguage] = [
        "c#": .cSharp,
        "csharp": .cSharp,
        "c-sharp": .cSharp,
        "c++": .cpp,
        "js": .javascript,
        "ts": .typescript,
        "markdown_inline": .markdownInline,
        "markdown-inline": .markdownInline,
        "objective-c": .objc,
        "objectivec": .objc,
        "objc": .objc,
        "yml": .yaml,
        "go-mod": .goMod,
        "gomod": .goMod,
        "ocaml-interface": .ocamlInterface,
        "ocamlinterface": .ocamlInterface,
        "plaintext": .plainText,
        "plain-text": .plainText
    ]

    /// Resolves an injection query language name, including common aliases.
    static func fromInjectionName(_ name: String) -> TreeSitterLanguage? {
        if let exact = TreeSitterLanguage(rawValue: name) {
            return exact
        }
        let normalized = name.lowercased()
        if let alias = injectionAliases[normalized] {
            return alias
        }
        return TreeSitterLanguage(rawValue: normalized)
    }
}
