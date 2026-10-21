import Foundation

/// A stable identifier for a language.
///
/// Built-in languages use the same raw values as ``TreeSitterLanguage``. The wrapper keeps language identity
/// extensible without requiring every consumer to know about a closed enum.
public struct LanguageID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ treeSitterLanguage: TreeSitterLanguage) {
        self.init(rawValue: treeSitterLanguage.rawValue)
    }

    /// The legacy built-in enum value, or `nil` for a contributed language.
    public var treeSitterLanguage: TreeSitterLanguage? {
        TreeSitterLanguage(rawValue: rawValue)
    }

    public static let agda = LanguageID(.agda)
    public static let apacheconf = LanguageID(.apacheconf)
    public static let bash = LanguageID(.bash)
    public static let c = LanguageID(.c)
    public static let cpp = LanguageID(.cpp)
    public static let cSharp = LanguageID(.cSharp)
    public static let css = LanguageID(.css)
    public static let dart = LanguageID(.dart)
    public static let dockerfile = LanguageID(.dockerfile)
    public static let dotenv = LanguageID(.dotenv)
    public static let elixir = LanguageID(.elixir)
    public static let gitignore = LanguageID(.gitignore)
    public static let go = LanguageID(.go)
    public static let goMod = LanguageID(.goMod)
    public static let haskell = LanguageID(.haskell)
    public static let html = LanguageID(.html)
    public static let java = LanguageID(.java)
    public static let javascript = LanguageID(.javascript)
    public static let jsdoc = LanguageID(.jsdoc)
    public static let json = LanguageID(.json)
    public static let jsx = LanguageID(.jsx)
    public static let julia = LanguageID(.julia)
    public static let kotlin = LanguageID(.kotlin)
    public static let lua = LanguageID(.lua)
    public static let markdown = LanguageID(.markdown)
    public static let markdownInline = LanguageID(.markdownInline)
    public static let objc = LanguageID(.objc)
    public static let ocaml = LanguageID(.ocaml)
    public static let ocamlInterface = LanguageID(.ocamlInterface)
    public static let perl = LanguageID(.perl)
    public static let php = LanguageID(.php)
    public static let python = LanguageID(.python)
    public static let regex = LanguageID(.regex)
    public static let ruby = LanguageID(.ruby)
    public static let rust = LanguageID(.rust)
    public static let scala = LanguageID(.scala)
    public static let sql = LanguageID(.sql)
    public static let swift = LanguageID(.swift)
    public static let toml = LanguageID(.toml)
    public static let tsx = LanguageID(.tsx)
    public static let typescript = LanguageID(.typescript)
    public static let verilog = LanguageID(.verilog)
    public static let yaml = LanguageID(.yaml)
    public static let zig = LanguageID(.zig)
    public static let plainText = LanguageID(.plainText)
}

public extension TreeSitterLanguage {
    var languageID: LanguageID {
        LanguageID(self)
    }
}

public extension LanguageID {
    /// Resolves an injection query language name, including common aliases.
    static func fromInjectionName(_ name: String) -> LanguageID? {
        if let builtIn = TreeSitterLanguage.fromInjectionName(name) {
            return builtIn.languageID
        }
        return LanguageCatalog.builtIn.language(forIdentifier: name)?.id
    }
}
