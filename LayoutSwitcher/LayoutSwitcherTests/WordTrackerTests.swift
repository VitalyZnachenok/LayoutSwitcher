import XCTest
@testable import LayoutSwitcher

final class WordTrackerTests: XCTestCase {
    private func type(_ text: String, into tracker: inout WordTracker) -> [String] {
        var finished: [String] = []
        for ch in text {
            let event: WordTracker.Event
            if ch == " " { event = .space }
            else if ch == "\n" { event = .newline }
            else if WordTracker.isWordCharacter(ch) { event = .character(ch) }
            else { event = .punctuation }
            if let word = tracker.feed(event) { finished.append(word) }
        }
        return finished
    }
    
    func testWordBeforeCursor() {
        var t = WordTracker()
        _ = type("ghbdtn", into: &t)
        XCTAssertEqual(t.snapshot, .init(wordLength: 6, wordBeforeBoundaryLength: 0, boundaryCount: 0))
        XCTAssertEqual(t.typingBuffer, "ghbdtn")
    }
    
    func testWordBeforeSpacesIsRemembered() {
        var t = WordTracker()
        let finished = type("ghbdtn  ", into: &t)
        XCTAssertEqual(finished, ["ghbdtn"])
        XCTAssertEqual(t.snapshot, .init(wordLength: 0, wordBeforeBoundaryLength: 6, boundaryCount: 2))
    }
    
    func testPunctuationFinishesWordAndClearsBoundary() {
        var t = WordTracker()
        let finished = type("hello,", into: &t)
        XCTAssertEqual(finished, ["hello"])
        XCTAssertEqual(t.snapshot, WordTracker.Snapshot())
    }
    
    func testBackspaceShortensWordThenResets() {
        var t = WordTracker()
        _ = type("abc", into: &t)
        t.feed(.backspace)
        XCTAssertEqual(t.snapshot.wordLength, 2)
        XCTAssertEqual(t.typingBuffer, "ab")
        t.feed(.backspace); t.feed(.backspace)
        XCTAssertEqual(t.snapshot.wordLength, 0)
        t.feed(.backspace)  // нечего стирать — сброс
        XCTAssertEqual(t, WordTracker())
    }
    
    func testCursorMoveAndCommandReset() {
        var t = WordTracker()
        _ = type("abc ", into: &t)
        t.feed(.cursorMove)
        XCTAssertEqual(t.snapshot, WordTracker.Snapshot())
        _ = type("abc", into: &t)
        t.feed(.command)
        XCTAssertEqual(t.snapshot, WordTracker.Snapshot())
    }
    
    func testNewlineFinishesWordAndResets() {
        var t = WordTracker()
        let finished = type("word\n", into: &t)
        XCTAssertEqual(finished, ["word"])
        XCTAssertEqual(t, WordTracker())
    }
    
    func testBufferIsCapped() {
        var t = WordTracker(maxBufferLength: 4)
        _ = type("abcdefg", into: &t)
        XCTAssertEqual(t.typingBuffer, "defg")
        XCTAssertEqual(t.snapshot.wordLength, 7)
    }
    
    func testApostropheAndHyphenAreWordCharacters() {
        var t = WordTracker()
        let finished = type("don't-stop ", into: &t)
        XCTAssertEqual(finished, ["don't-stop"])
    }
    
    func testRestoreKeepsCountersAndClearsBuffer() {
        var t = WordTracker()
        _ = type("ghbdtn", into: &t)
        let snapshot = t.snapshot
        t.reset()
        t.restore(snapshot)
        XCTAssertEqual(t.snapshot.wordLength, 6)
        XCTAssertEqual(t.typingBuffer, "")
        // Уже сконвертированное слово детектору повторно не отдаётся.
        XCTAssertNil(t.feed(.space))
        XCTAssertEqual(t.snapshot.wordBeforeBoundaryLength, 6)
        XCTAssertEqual(t.snapshot.boundaryCount, 1)
    }
}
