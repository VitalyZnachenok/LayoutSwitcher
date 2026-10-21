import XCTest
@testable import LayoutSwitcher

final class NGramTests: XCTestCase {
    private let detector = NGramLayoutDetector(bundle: .main)
    
    func testModelsAreBundled() {
        for lang in ["ru", "en", "uk", "de"] {
            XCTAssertNotNil(NGramLanguageModel.load(language: lang), "missing model for \(lang)")
        }
        XCTAssertNil(NGramLanguageModel.load(language: "xx"))
    }
    
    func testScoresPreferOwnLanguage() throws {
        let ru = try XCTUnwrap(NGramLanguageModel.load(language: "ru"))
        let en = try XCTUnwrap(NGramLanguageModel.load(language: "en"))
        XCTAssertGreaterThan(ru.score("привет"), ru.score("ghbdtn"))
        XCTAssertGreaterThan(en.score("hello"), en.score("руддщ"))
        XCTAssertEqual(ru.score("hello"), NGramLanguageModel.unknownScore)
    }
    
    func testWrongLayoutDetected() {
        XCTAssertEqual(detector.isWrongLayout(word: "ghbdtn", converted: "привет", typedLanguage: "en", otherLanguage: "ru"), true)
        XCTAssertEqual(detector.isWrongLayout(word: "руддщ", converted: "hello", typedLanguage: "ru", otherLanguage: "en"), true)
        XCTAssertEqual(detector.isWrongLayout(word: "cjj,otybt", converted: "сообщение", typedLanguage: "en", otherLanguage: "ru"), true)
        // Несловарное слово — имя.
        XCTAssertEqual(detector.isWrongLayout(word: "Dbnfkbq", converted: "Виталий", typedLanguage: "en", otherLanguage: "ru"), true)
    }
    
    func testCorrectTypingNotFlagged() {
        XCTAssertEqual(detector.isWrongLayout(word: "hello", converted: "руддщ", typedLanguage: "en", otherLanguage: "ru"), false)
        XCTAssertEqual(detector.isWrongLayout(word: "привет", converted: "ghbdtn", typedLanguage: "ru", otherLanguage: "en"), false)
        XCTAssertEqual(detector.isWrongLayout(word: "statistics", converted: "ыефешыешсы", typedLanguage: "en", otherLanguage: "ru"), false)
        XCTAssertEqual(detector.isWrongLayout(word: "сообщение", converted: "cjj,otybt", typedLanguage: "ru", otherLanguage: "en"), false)
    }
    
    func testMissingModelReturnsNil() {
        XCTAssertNil(detector.isWrongLayout(word: "hola", converted: "рщдф", typedLanguage: "es", otherLanguage: "ru"))
    }
    
    func testFalsePositiveRateOnDictionaryWords() throws {
        // Небольшой контроль порога на обычных словах обоих языков.
        let en = ["because", "between", "through", "example", "keyboard", "layout", "switch", "window", "people", "thing"]
        let ru = ["потому", "между", "через", "пример", "клавиатура", "раскладка", "окно", "люди", "дело", "время"]
        for w in en {
            XCTAssertEqual(detector.isWrongLayout(word: w, converted: LayoutConverter.convert(w, currentLayoutIsRussian: false),
                                                  typedLanguage: "en", otherLanguage: "ru"), false, w)
        }
        for w in ru {
            XCTAssertEqual(detector.isWrongLayout(word: w, converted: LayoutConverter.convert(w, currentLayoutIsRussian: true),
                                                  typedLanguage: "ru", otherLanguage: "en"), false, w)
        }
    }
}
