import XCTest
@testable import CodeEditLanguages

/// Contributed languages come from extension syntax packs: they reuse a bundled grammar but ship their
/// own queries, detection metadata, and aliases.
final class ContributedLanguageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeQuery(_ contents: String, name: String = "highlights.scm") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func contributedLanguage(
        highlightsSource: String = "(comment) @comment\n"
    ) throws -> CodeLanguage {
        let highlights = try writeQuery(highlightsSource)
        let injections = try writeQuery("((script_element) @injection.content\n (#set! injection.language \"javascript\"))\n",
                                        name: "injections.scm")
        return CodeLanguage(
            id: LanguageID(rawValue: "sample-template"),
            tsName: "html",
            extensions: ["tmpl"],
            lineCommentString: "",
            rangeCommentStrings: ("<!--", "-->"),
            grammar: GrammarReference(identifier: "html", builtInLanguage: .html),
            highlights: ["injections"],
            additionalIdentifiers: ["sample-template"],
            queryURLs: ["highlights": highlights, "injections": injections],
            firstLinePatterns: ["^\\s*\\{\\{!.*\\}\\}\\s*$"]
        )
    }

    func testContributedLanguageReusesBuiltInGrammarAndOwnQueries() throws {
        let language = try contributedLanguage()

        XCTAssertNotNil(language.language, "A contributed language must resolve the built-in grammar.")
        XCTAssertEqual(language.queryURL?.deletingLastPathComponent(), directory)
        XCTAssertEqual(language.querySet?.injections?.deletingLastPathComponent(), directory)
        XCTAssertEqual(language.querySet?.sourceURLs.count, 3)
    }

    func testContributedLanguageQueriesCompile() throws {
        let language = try contributedLanguage()
        let catalog = LanguageCatalog(languages: CodeLanguage.allLanguages + [.default, language])

        let query = TreeSitterModel.shared.query(for: language.id, catalog: catalog)
        XCTAssertNotNil(query)
    }

    func testContributedLanguageFingerprintTracksQueryContent() throws {
        let first = try contributedLanguage()
        let firstFingerprint = first.fingerprint

        let second = try contributedLanguage(highlightsSource: "(comment) @comment\n(string) @string\n")

        XCTAssertNotEqual(firstFingerprint, second.fingerprint)
    }

    func testDetectionPrefersFileNameThenExtensionThenFirstLine() throws {
        let language = try contributedLanguage()
        let catalog = LanguageCatalog(languages: CodeLanguage.allLanguages + [.default, language])

        XCTAssertEqual(
            catalog.detectLanguage(url: URL(fileURLWithPath: "/tmp/page.tmpl")).id,
            language.id
        )
        XCTAssertEqual(
            catalog.detectLanguage(
                url: URL(fileURLWithPath: "/tmp/unknown-extension.xyz"),
                prefix: "{{! sample template }}\n"
            ).id,
            language.id
        )
        // An extension mapping always wins over a first-line pattern.
        XCTAssertEqual(
            catalog.detectLanguage(
                url: URL(fileURLWithPath: "/tmp/page.php"),
                prefix: "{{! sample template }}\n"
            ).id,
            .php
        )
    }

    func testContributedLanguageDoesNotShadowBuiltInMappings() throws {
        let language = CodeLanguage(
            id: LanguageID(rawValue: "contributed-html"),
            tsName: "html",
            extensions: ["html"],
            lineCommentString: "",
            rangeCommentStrings: ("<!--", "-->"),
            grammar: GrammarReference(identifier: "html", builtInLanguage: .html)
        )
        // Built-ins are ordered first, so a contributed pack cannot hijack an existing extension.
        let catalog = LanguageCatalog(languages: CodeLanguage.allLanguages + [.default, language])
        XCTAssertEqual(catalog.detectLanguage(url: URL(fileURLWithPath: "/tmp/index.html")).id, .html)

        // With the pack ordered first it wins, which is how workspace packs are layered explicitly.
        let packFirst = LanguageCatalog(languages: [language] + CodeLanguage.allLanguages + [.default])
        XCTAssertEqual(packFirst.detectLanguage(url: URL(fileURLWithPath: "/tmp/index.html")).id, language.id)
    }

    func testShebangDetectionUsesContributedIdentifiers() throws {
        let language = CodeLanguage(
            id: LanguageID(rawValue: "sample-script"),
            tsName: "bash",
            extensions: ["sample"],
            lineCommentString: "#",
            rangeCommentStrings: ("", ""),
            grammar: GrammarReference(identifier: "bash", builtInLanguage: .bash),
            additionalIdentifiers: ["samplescript"]
        )
        let catalog = LanguageCatalog(languages: CodeLanguage.allLanguages + [.default, language])

        XCTAssertEqual(
            catalog.detectLanguage(
                url: URL(fileURLWithPath: "/tmp/tool"),
                prefix: "#!/usr/bin/env samplescript\n"
            ).id,
            language.id
        )
    }

    func testCatalogAliasResolutionIncludesContributedIdentifiers() throws {
        let language = try contributedLanguage()
        let catalog = LanguageCatalog(languages: CodeLanguage.allLanguages + [.default, language])
        XCTAssertEqual(catalog.language(forIdentifier: "sample-template")?.id, language.id)
    }

    func testUnknownExtensionFallsBackToPlainText() {
        XCTAssertEqual(
            LanguageCatalog.builtIn.detectLanguage(url: URL(fileURLWithPath: "/tmp/file.unknown-ext")).id,
            .plainText
        )
    }

    // MARK: Bundled samples

    /// The shipped query-only sample pack (`samples/extensions/geojson-pack`) reuses the JSON grammar
    /// and replaces its highlights query wholesale, so its query must compile against that grammar.
    func testBundledGeoJSONSampleQueryCompiles() throws {
        guard let samples = Self.samplesExtensionsDirectory() else {
            throw XCTSkip("Bundled samples are not present next to the package.")
        }
        let highlights = samples.appendingPathComponent("geojson-pack/queries/highlights.scm")
        guard FileManager.default.fileExists(atPath: highlights.path) else {
            throw XCTSkip("The GeoJSON sample pack is not present.")
        }

        // Mirrors what the extension loader builds for `"grammar": { "kind": "builtin", "name": "json" }`.
        let language = CodeLanguage(
            id: LanguageID(rawValue: "geojson"),
            tsName: "GeoJSON",
            extensions: ["geojson"],
            lineCommentString: CodeLanguage.json.lineCommentString,
            rangeCommentStrings: CodeLanguage.json.rangeCommentStrings,
            grammar: GrammarReference(identifier: "json", builtInLanguage: .json),
            queryURLs: ["highlights": highlights]
        )

        let captures = try language.compileQuery(at: highlights)
        XCTAssertTrue(captures.contains("property"), "Missing GeoJSON key rule: \(captures)")
        XCTAssertTrue(captures.contains("constant"), "Missing GeoJSON type-value rule: \(captures)")
        XCTAssertTrue(captures.contains("string.special.key"), "Missing generic key rule: \(captures)")
    }

    private static func samplesExtensionsDirectory() -> URL? {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("samples/extensions")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
