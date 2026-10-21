import XCTest
@testable import LayoutSwitcher

final class AXWordRangeTests: XCTestCase {
    private func range(_ text: String, caret: Int) -> String? {
        let ns = text as NSString
        guard let r = AXTextAccess.lastWordRange(in: ns, before: caret) else { return nil }
        return ns.substring(with: r)
    }
    
    func testWordDirectlyBeforeCaret() {
        XCTAssertEqual(range("hello ghbdtn", caret: 12), "ghbdtn")
        XCTAssertEqual(range("ghbdtn", caret: 6), "ghbdtn")
    }
    
    func testWordBeforeSpacesAndPunctuation() {
        XCTAssertEqual(range("hello ghbdtn  ", caret: 14), "ghbdtn")
        XCTAssertEqual(range("hello ghbdtn, ", caret: 14), "ghbdtn")
        XCTAssertNil(range("word      ", caret: 10))  // слишком далеко от курсора
    }
    
    func testCaretInsideTextUsesPrefixOnly() {
        XCTAssertEqual(range("hello world", caret: 5), "hello")
        XCTAssertEqual(range("hello world", caret: 3), "hel")
    }
    
    func testNewlineStopsSearch() {
        XCTAssertNil(range("word\n", caret: 5))
        XCTAssertNil(range("", caret: 0))
        XCTAssertNil(range("   ", caret: 3))
    }
    
    func testCyrillicAndUTF16Offsets() {
        let text = "😀 привет"
        let ns = text as NSString
        let r = AXTextAccess.lastWordRange(in: ns, before: ns.length)
        XCTAssertEqual(r.map { ns.substring(with: $0) }, "привет")
        XCTAssertEqual(r?.location, 3)  // эмодзи занимает две UTF-16 единицы + пробел
    }
    
    func testOutOfRangeCaret() {
        XCTAssertNil(range("abc", caret: 10))
        XCTAssertNil(range("abc", caret: -1))
    }
}
