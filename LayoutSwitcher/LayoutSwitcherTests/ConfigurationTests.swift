import XCTest
@testable import LayoutSwitcher

final class ConfigurationTests: XCTestCase {
    func testDecodingOldConfigurationFillsDefaults() throws {
        let json = """
        {"keyCode":37,"modifierFlags":1179648,"keyCharacter":"L","hotKeyMode":"doubleShift"}
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(HotKeyConfiguration.self, from: json)
        XCTAssertEqual(cfg.hotKeyMode, .doubleShift)
        XCTAssertEqual(cfg.detectionEngine, .ngram)
        XCTAssertTrue(cfg.useAccessibilityReplacement)
        XCTAssertEqual(cfg.minWordLength, 3)
    }
    
    func testRoundTrip() throws {
        var cfg = HotKeyConfiguration()
        cfg.useAccessibilityReplacement = false
        cfg.layout1ID = "com.apple.keylayout.US"
        let data = try JSONEncoder().encode(cfg)
        XCTAssertEqual(try JSONDecoder().decode(HotKeyConfiguration.self, from: data), cfg)
    }
    
    func testDisplayString() {
        var cfg = HotKeyConfiguration()
        XCTAssertEqual(cfg.displayString, "⇧⌘L")
        cfg.hotKeyMode = .doubleAlt
        XCTAssertEqual(cfg.displayString, "⌥⌥")
    }
    
    @MainActor
    func testMetricsPersist() {
        let suite = "LayoutSwitcherTests.metrics"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        
        let m = ConversionMetrics(defaults: defaults)
        m.recordSuccess(duration: 0.1, viaAccessibility: true)
        m.recordFailure()
        
        let reloaded = ConversionMetrics(defaults: defaults)
        XCTAssertEqual(reloaded.totalConversions, 2)
        XCTAssertEqual(reloaded.successfulConversions, 1)
        XCTAssertEqual(reloaded.accessibilityConversions, 1)
        XCTAssertEqual(reloaded.averageConversionTime, 0.1, accuracy: 0.0001)
        defaults.removePersistentDomain(forName: suite)
    }
}
