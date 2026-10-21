import XCTest
@testable import LayoutSwitcher

final class HotkeyRecognizerTests: XCTestCase {
    func testExactModifierMatch() {
        let expected: CGEventFlags = [.maskCommand, .maskShift]
        XCTAssertTrue(HotkeyMatcher.matches(keyCode: 0x25, flags: [.maskCommand, .maskShift],
                                            expectedKeyCode: 0x25, expectedFlags: expected))
        // Лишний модификатор больше не считается совпадением.
        XCTAssertFalse(HotkeyMatcher.matches(keyCode: 0x25, flags: [.maskCommand, .maskShift, .maskControl],
                                             expectedKeyCode: 0x25, expectedFlags: expected))
        XCTAssertFalse(HotkeyMatcher.matches(keyCode: 0x25, flags: [.maskCommand],
                                             expectedKeyCode: 0x25, expectedFlags: expected))
        XCTAssertFalse(HotkeyMatcher.matches(keyCode: 0x26, flags: [.maskCommand, .maskShift],
                                             expectedKeyCode: 0x25, expectedFlags: expected))
    }
    
    func testIrrelevantFlagsAreIgnored() {
        let expected: CGEventFlags = [.maskCommand, .maskShift]
        // Caps Lock, NumPad и "non-coalesced" не должны мешать.
        XCTAssertTrue(HotkeyMatcher.matches(keyCode: 0x25, flags: [.maskCommand, .maskShift, .maskAlphaShift, .maskNonCoalesced],
                                            expectedKeyCode: 0x25, expectedFlags: expected))
    }
    
    func testNSEventAndCGEventFlagBitsAgree() {
        // Конфигурация хранит NSEvent.ModifierFlags, а сравнение идёт в CGEventFlags.
        let ns = NSEvent.ModifierFlags([.command, .shift, .option, .control]).rawValue
        let cg: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        XCTAssertEqual(UInt64(ns), cg.rawValue)
    }
    
    func testDoubleTapWithinWindow() {
        var d = DoubleTapDetector(minInterval: 0.05, maxInterval: 0.8)
        XCTAssertFalse(d.press(at: 10.0))
        XCTAssertTrue(d.press(at: 10.3))
        // После срабатывания серия начинается заново.
        XCTAssertFalse(d.press(at: 10.5))
    }
    
    func testDoubleTapTooSlowOrTooFast() {
        var d = DoubleTapDetector(minInterval: 0.05, maxInterval: 0.8)
        XCTAssertFalse(d.press(at: 10.0))
        XCTAssertFalse(d.press(at: 11.0))   // слишком поздно — новая серия
        XCTAssertTrue(d.press(at: 11.4))
        
        var bounce = DoubleTapDetector(minInterval: 0.05, maxInterval: 0.8)
        XCTAssertFalse(bounce.press(at: 20.0))
        XCTAssertFalse(bounce.press(at: 20.01))  // дребезг — игнорируется
        XCTAssertTrue(bounce.press(at: 20.3))
    }
    
    func testKeyBetweenTapsCancelsSeries() {
        // «Hello World»: Shift, буквы, Shift — не двойное нажатие.
        var d = DoubleTapDetector(minInterval: 0.05, maxInterval: 0.8)
        XCTAssertFalse(d.press(at: 10.0))
        d.cancel()
        XCTAssertFalse(d.press(at: 10.3))
        XCTAssertTrue(d.press(at: 10.6))
    }
}
