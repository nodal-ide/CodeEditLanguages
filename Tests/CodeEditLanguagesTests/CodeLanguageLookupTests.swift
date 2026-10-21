import XCTest
@testable import CodeEditLanguages

final class CodeLanguageLookupTests: XCTestCase {
    func testLanguageByID() {
        XCTAssertEqual(CodeLanguage.languageForID(.php)?.id, .php)
        XCTAssertEqual(CodeLanguage.languageForID(.cSharp)?.id, .cSharp)
        XCTAssertEqual(CodeLanguage.languageForID(.markdownInline)?.id, .markdownInline)
    }

    func testLanguageByExtension() {
        XCTAssertEqual(CodeLanguage.languageForExtension("php")?.id, .php)
        XCTAssertEqual(CodeLanguage.languageForExtension("SWIFT")?.id, .swift)
        XCTAssertEqual(CodeLanguage.languageForExtension("cs")?.id, .cSharp)
    }

    func testLanguageByFileName() {
        XCTAssertEqual(CodeLanguage.languageForFileName("Dockerfile")?.id, .dockerfile)
        XCTAssertNil(CodeLanguage.languageForFileName("UnknownFile"))
    }

    func testLanguageByIdentifierAliases() {
        XCTAssertEqual(CodeLanguage.languageForIdentifier("js")?.id, .javascript)
        XCTAssertEqual(CodeLanguage.languageForIdentifier("ts")?.id, .typescript)
        XCTAssertEqual(CodeLanguage.languageForIdentifier("sh")?.id, .bash)
        XCTAssertEqual(CodeLanguage.languageForIdentifier("markdown_inline")?.id, .markdownInline)
        XCTAssertEqual(CodeLanguage.languageForIdentifier("c#")?.id, .cSharp)
        XCTAssertNil(CodeLanguage.languageForIdentifier("not-a-language"))
    }

    func testInjectionAliases() {
        XCTAssertEqual(TreeSitterLanguage.fromInjectionName("js"), .javascript)
        XCTAssertEqual(TreeSitterLanguage.fromInjectionName("markdown_inline"), .markdownInline)
        XCTAssertEqual(TreeSitterLanguage.fromInjectionName("yml"), .yaml)
        XCTAssertEqual(TreeSitterLanguage.fromInjectionName("c#"), .cSharp)
        XCTAssertNil(TreeSitterLanguage.fromInjectionName("not-a-language"))
    }
}
