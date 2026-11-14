import Foundation
import XCTest
@testable import HandyKit

final class PhraseReplacementTests: XCTestCase {
    private func rule(_ phrase: String, _ replacement: String) -> ReplacementRule {
        ReplacementRule(phrase: phrase, replacement: replacement)
    }

    func testBoundariesCaseAndPunctuation() {
        XCTAssertEqual(PhraseReplacement.apply("Teh, TEH! otherteh teh2 _teh teh_ (teh).", rules: [rule("teh", "the")]),
                       "the, the! otherteh teh2 _teh teh_ (the).")
        XCTAssertEqual(PhraseReplacement.apply("a.b aXb C++!", rules: [rule("a.b", "$1"), rule("C++", "Swift")]), "$1 aXb Swift!")
    }

    func testPhrasesRequireLiteralSpacing() {
        XCTAssertEqual(PhraseReplacement.apply("new york, new  york; new yorker", rules: [rule("new york", "NY")]),
                       "NY, new  york; new yorker")
    }

    func testOverlapUsesRuleOrderEvenWhenLaterMatchStartsEarlier() {
        let rules = [rule("york city", "YC"), rule("new york", "NY")]
        XCTAssertEqual(PhraseReplacement.apply("new york city", rules: rules), "new YC")
        XCTAssertEqual(PhraseReplacement.apply("new york city", rules: rules.reversed()), "NY city")
    }

    func testNoCascadeAndRepeatedMatches() {
        XCTAssertEqual(PhraseReplacement.apply("a a", rules: [rule("a", "b"), rule("b", "c")]), "b b")
        XCTAssertEqual(PhraseReplacement.apply("x x", rules: [rule("", "bad"), rule(" ", "bad"), rule("x", "")]), " ")
        XCTAssertEqual(PhraseReplacement.apply("", rules: [rule("x", "y")]), "")
        XCTAssertEqual(PhraseReplacement.apply("unchanged", rules: []), "unchanged")
    }

    func testUnicodeWordsAndExactReplacementCase() {
        XCTAssertEqual(PhraseReplacement.apply("CAFÉ café cafés 中文 中文字 😀café", rules: [rule("café", "Coffee"), rule("中文", "Chinese")]),
                       "Coffee Coffee cafés Chinese 中文字 😀Coffee")
        XCTAssertEqual(PhraseReplacement.apply("e\u{301} e", rules: [rule("e", "X")]), "e\u{301} X")
        XCTAssertEqual(PhraseReplacement.apply("😀!", rules: [rule("😀", "Hi")]), "Hi!")
    }

    func testDuplicateIgnoresCaseAndExcludesEditedRule() {
        let saved = rule("Teh", "the")
        XCTAssertTrue(PhraseReplacement.isDuplicate("teh", in: [saved]))
        XCTAssertFalse(PhraseReplacement.isDuplicate("teh", in: [saved], excluding: saved.id))
    }

    func testPersistenceAndLegacyFormats() throws {
        let name = "PhraseReplacementTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("existing", forKey: "unrelated")
        let storage = UserDefaultsReplacementStorage(defaults: defaults)
        XCTAssertEqual(storage.load(), [])
        let rules = [rule("one", "two"), rule("two", "three")]
        try storage.save(rules)
        XCTAssertEqual(UserDefaultsReplacementStorage(defaults: defaults).load(), rules)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "existing")
        defaults.set(try JSONEncoder().encode(rules), forKey: UserDefaultsReplacementStorage.key)
        XCTAssertEqual(storage.load(), rules)
        defaults.set(Data("{bad".utf8), forKey: UserDefaultsReplacementStorage.key)
        XCTAssertEqual(storage.load(), [])
        defaults.set(Data("{\"version\":99,\"rules\":[]}".utf8), forKey: UserDefaultsReplacementStorage.key)
        XCTAssertEqual(storage.load(), [])
    }
}
