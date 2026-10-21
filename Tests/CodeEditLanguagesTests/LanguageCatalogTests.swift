import XCTest
@testable import CodeEditLanguages

final class LanguageCatalogTests: XCTestCase {
    func testLanguageIDBridgesBuiltInLanguages() {
        XCTAssertEqual(LanguageID.php.treeSitterLanguage, .php)
        XCTAssertEqual(TreeSitterLanguage.php.languageID, .php)
        XCTAssertEqual(LanguageID.fromInjectionName("c++"), .cpp)
    }

    func testCatalogLookupPrecedenceAndAliases() {
        let catalog = LanguageCatalog.builtIn
        XCTAssertEqual(catalog.language(for: .php)?.id, .php)
        XCTAssertEqual(catalog.language(forFileExtension: "PHP")?.id, .php)
        XCTAssertEqual(catalog.language(forFileName: "Dockerfile")?.id, .dockerfile)
        XCTAssertEqual(catalog.language(forIdentifier: "js")?.id, .javascript)
        XCTAssertEqual(catalog.language(forIdentifier: "markdown_inline")?.id, .markdownInline)
        XCTAssertEqual(catalog.language(forIdentifier: "ts")?.id, .typescript)
        XCTAssertNil(catalog.language(forIdentifier: "not-a-language"))
    }

    func testLegacyLookupDelegatesToCatalog() {
        XCTAssertEqual(CodeLanguage.languageForID(.cSharp)?.id, .cSharp)
        XCTAssertEqual(CodeLanguage.languageForExtension("rs")?.id, .rust)
        XCTAssertEqual(CodeLanguage.languageForFileName("Dockerfile")?.id, .dockerfile)
        XCTAssertEqual(CodeLanguage.languageForIdentifier("shell")?.id, .bash)
    }

    func testQuerySetIncludesParentAndInjectionQueries() {
        XCTAssertNotNil(CodeLanguage.cpp.querySet?.parentHighlights)
        XCTAssertNotNil(CodeLanguage.php.querySet?.injections)
        let hasHighlights = CodeLanguage.php.definition.querySet?.sourceURLs.contains {
            $0.lastPathComponent == "highlights.scm"
        } ?? false
        XCTAssertTrue(hasHighlights)
    }

    func testFingerprintIsStableAndChangesWithMetadata() {
        let original = CodeLanguage.php
        let same = CodeLanguage(
            id: original.id,
            tsName: original.tsName,
            extensions: original.extensions,
            lineCommentString: original.lineCommentString,
            rangeCommentStrings: original.rangeCommentStrings,
            grammar: original.grammar,
            parentURL: original.parentQueryURL,
            highlights: original.additionalHighlights,
            additionalIdentifiers: original.additionalIdentifiers
        )
        let changedGrammar = CodeLanguage(
            id: original.id,
            tsName: original.tsName,
            extensions: original.extensions,
            lineCommentString: original.lineCommentString,
            rangeCommentStrings: original.rangeCommentStrings,
            grammar: GrammarReference(identifier: "php-next"),
            parentURL: original.parentQueryURL,
            highlights: original.additionalHighlights,
            additionalIdentifiers: original.additionalIdentifiers
        )

        XCTAssertEqual(original.fingerprint, same.fingerprint)
        XCTAssertNotEqual(original.fingerprint, changedGrammar.fingerprint)
    }

    func testQueryCompilationIsCachedByFingerprint() {
        let first = TreeSitterModel.shared.query(for: .php)
        let second = TreeSitterModel.shared.query(for: .php)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
    }

    func testCatalogVersionIncludesContributedLanguage() {
        let custom = CodeLanguage(
            id: LanguageID(rawValue: "custom"),
            tsName: "custom",
            extensions: ["custom"],
            lineCommentString: "//",
            rangeCommentStrings: ("/*", "*/"),
            grammar: GrammarReference(identifier: "custom")
        )
        let catalog = LanguageCatalog(languages: [.php, custom])
        XCTAssertEqual(catalog.language(for: LanguageID(rawValue: "custom"))?.id.rawValue, "custom")
        XCTAssertEqual(catalog.language(forFileExtension: "custom")?.id.rawValue, "custom")
    }
}

extension LanguageCatalogTests {
    func testFingerprintAndQueryCacheInvalidateWhenQueryContentChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let languageDirectory = root.appendingPathComponent("tree-sitter-php", isDirectory: true)
        try FileManager.default.createDirectory(at: languageDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let queryURL = languageDirectory.appendingPathComponent("highlights.scm")
        try "(comment) @comment\n".write(to: queryURL, atomically: true, encoding: .utf8)

        func language() -> CodeLanguage {
            let original = CodeLanguage.php
            return CodeLanguage(
                id: original.id,
                tsName: original.tsName,
                extensions: original.extensions,
                lineCommentString: original.lineCommentString,
                rangeCommentStrings: original.rangeCommentStrings,
                grammar: original.grammar,
                parentURL: original.parentQueryURL,
                highlights: original.additionalHighlights,
                additionalIdentifiers: original.additionalIdentifiers,
                resourceURL: root
            )
        }

        let first = language()
        let firstFingerprint = first.fingerprint
        let firstQuery = TreeSitterModel.shared.query(for: first.id, catalog: LanguageCatalog(languages: [first]))
        XCTAssertNotNil(firstQuery)

        try "(comment) @comment\n(string) @string\n".write(to: queryURL, atomically: true, encoding: .utf8)
        let second = language()
        XCTAssertNotEqual(firstFingerprint, second.fingerprint)
        let secondQuery = TreeSitterModel.shared.query(for: second.id, catalog: LanguageCatalog(languages: [second]))
        XCTAssertNotNil(secondQuery)
        XCTAssertFalse(firstQuery === secondQuery)
    }
}
