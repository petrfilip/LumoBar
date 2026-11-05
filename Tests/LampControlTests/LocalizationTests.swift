import XCTest

/// Guards the hand-maintained Localizable.strings files (en, fr, es, cs) against drift.
final class LocalizationTests: XCTestCase {
    private static let languages = ["en", "fr", "es", "cs"]

    private static var packageRoot: URL {
        // <root>/Tests/LampControlTests/LocalizationTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private static var sourcesDir: URL { packageRoot.appendingPathComponent("Sources/LampControl") }

    private func strings(_ lang: String) throws -> [String: String] {
        let url = Self.sourcesDir.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(lang) is not a string dictionary")
    }

    /// Printf specifiers (`%@`, `%d`, `%1$@`, `%.2f`, ...), ignoring the literal `%%`.
    private func specifiers(_ value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDuUxXoOfFeEgGcCsSpaA]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let cleaned = value.replacingOccurrences(of: "%%", with: "")
        let ns = cleaned as NSString
        return regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    func testAllLanguagesParseAndAreNonEmpty() throws {
        for lang in Self.languages {
            let table = try strings(lang)
            XCTAssertGreaterThan(table.count, 100, lang)
        }
    }

    func testIdenticalKeySetsAcrossLanguages() throws {
        let en = Set(try strings("en").keys)
        for lang in Self.languages where lang != "en" {
            let keys = Set(try strings(lang).keys)
            XCTAssertEqual(en.subtracting(keys).sorted(), [], "keys missing in \(lang)")
            XCTAssertEqual(keys.subtracting(en).sorted(), [], "keys in \(lang) but not in en")
        }
    }

    func testNoEmptyTranslations() throws {
        for lang in Self.languages {
            for (key, value) in try strings(lang) {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(lang): \(key) is empty")
            }
        }
    }

    func testFormatSpecifiersMatchEnglishPerKey() throws {
        let en = try strings("en")
        for lang in Self.languages where lang != "en" {
            let table = try strings(lang)
            for (key, english) in en {
                guard let translated = table[key] else { continue }
                // Positional specifiers (%1$@) may legitimately reorder, so compare as multisets.
                XCTAssertEqual(specifiers(translated).sorted(), specifiers(english).sorted(),
                               "\(lang): format specifiers of \(key) differ from en")
            }
        }
    }

    func testSpecifierExtractor() {
        XCTAssertEqual(specifiers("%@ of %d (%.1f%%)"), ["%@", "%d", "%.1f"])
        XCTAssertEqual(specifiers("100%% sure"), [])
        XCTAssertEqual(specifiers("%2$@ %1$d"), ["%2$@", "%1$d"])
    }

    func testEveryNSLocalizedStringLiteralKeyExistsInEnglish() throws {
        let en = try strings("en")
        let regex = try NSRegularExpression(pattern: #"NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)""#)

        var found = 0
        var missing: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sourcesDir, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let key = ns.substring(with: match.range(at: 1))
                found += 1
                if en[key] == nil {
                    missing.append("\(url.lastPathComponent): \(key)")
                }
            }
        }
        XCTAssertGreaterThan(found, 50, "extractor found suspiciously few NSLocalizedString keys")
        XCTAssertEqual(missing, [], "NSLocalizedString keys with no entry in en.lproj")
    }

    func testEveryL10nHelperLiteralKeyExistsInEnglish() throws {
        // L10n.swift wraps NSLocalizedString in a private `s("key")` helper.
        let en = try strings("en")
        let text = try String(contentsOf: Self.sourcesDir.appendingPathComponent("L10n.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\bs\("([^"\\]+)"\)"#)
        let ns = text as NSString
        let keys = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
        XCTAssertGreaterThan(keys.count, 10)
        XCTAssertEqual(keys.filter { en[$0] == nil }, [])
    }
}
