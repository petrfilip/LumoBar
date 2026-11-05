import XCTest
@testable import LampControl

final class L10nPluralTests: XCTestCase {
    func testCzechPluralCategories() {
        XCTAssertEqual(L10n.pluralCategory(1, language: "cs"), .one)
        for n in 2...4 { XCTAssertEqual(L10n.pluralCategory(n, language: "cs"), .few) }
        for n in [0, 5, 11, 100] { XCTAssertEqual(L10n.pluralCategory(n, language: "cs"), .other) }
    }

    func testEnglishAndSpanishCategories() {
        for lang in ["en", "es"] {
            XCTAssertEqual(L10n.pluralCategory(1, language: lang), .one)
            XCTAssertEqual(L10n.pluralCategory(0, language: lang), .other)
            XCTAssertEqual(L10n.pluralCategory(2, language: lang), .other)
        }
    }

    func testFrenchTreatsZeroAsSingular() {
        XCTAssertEqual(L10n.pluralCategory(0, language: "fr"), .one)
        XCTAssertEqual(L10n.pluralCategory(1, language: "fr"), .one)
        XCTAssertEqual(L10n.pluralCategory(2, language: "fr"), .other)
    }

    func testEveryPluralKeyExistsInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for lang in ["en", "fr", "es", "cs"] {
            let url = root.appendingPathComponent("Sources/LampControl/Resources/\(lang).lproj/Localizable.strings")
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)
            let table = try XCTUnwrap(plist as? [String: String])
            for category in ["one", "few", "other"] {
                let value = try XCTUnwrap(table["room.lamps.count.\(category)"], "\(lang) \(category)")
                XCTAssertTrue(value.contains("%d"), "\(lang) \(category)")
            }
        }
    }
}
