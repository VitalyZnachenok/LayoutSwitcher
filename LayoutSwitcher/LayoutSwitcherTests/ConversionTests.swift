import XCTest
@testable import LayoutSwitcher

final class ConversionTests: XCTestCase {
    func testStaticTableBothDirections() {
        XCTAssertEqual(LayoutConverter.convert("ghbdtn"), "привет")
        XCTAssertEqual(LayoutConverter.convert("привет"), "ghbdtn")
        XCTAssertEqual(LayoutConverter.convert("Ghbdtn, vbh!"), "Приветб мир!")  // "," на US — это "б" в ЙЦУКЕН
        XCTAssertEqual(LayoutConverter.convert("руддщ", currentLayoutIsRussian: true), "hello")
    }
    
    func testDetectRussian() {
        XCTAssertTrue(LayoutConverter.detectRussian("привет"))
        XCTAssertFalse(LayoutConverter.detectRussian("hello"))
        XCTAssertTrue(LayoutConverter.detectRussian("ё"))
    }
    
    @MainActor
    func testDynamicMappingPicksDirectionByChangedCount() throws {
        let layouts = LayoutManager.installedLayouts().map { LayoutManager.sourceID($0) }
        guard layouts.contains(where: { $0.lowercased().contains("russian") }),
              layouts.contains(where: { $0.hasSuffix(".US") || $0.hasSuffix(".ABC") }) else {
            throw XCTSkip("Requires US/ABC and Russian layouts installed")
        }
        let r1 = try XCTUnwrap(DynamicKeyMapping.convert("ghbdtn", layout1ID: "", layout2ID: ""))
        XCTAssertEqual(r1.text, "привет")
        XCTAssertTrue(r1.targetLayoutID.lowercased().contains("russian"))
        
        let r2 = try XCTUnwrap(DynamicKeyMapping.convert("привет", layout1ID: "", layout2ID: ""))
        XCTAssertEqual(r2.text, "ghbdtn")
        
        // Смешанный текст: больше русских символов → направление ru→en.
        let mixed = try XCTUnwrap(DynamicKeyMapping.convert("ghbdtn привет мир", layout1ID: "", layout2ID: ""))
        XCTAssertEqual(mixed.text, "ghbdtn ghbdtn vbh")
        
        XCTAssertNil(DynamicKeyMapping.convert("12345", layout1ID: "", layout2ID: ""))
    }
    
    @MainActor
    func testDynamicDirectedConvert() throws {
        let (us, ru) = LayoutManager.resolvePair(layout1ID: "", layout2ID: "")
        guard !us.isEmpty, !ru.isEmpty else { throw XCTSkip("Requires a Latin and a Cyrillic layout") }
        XCTAssertEqual(DynamicKeyMapping.convert("ghbdtn", from: us, to: ru), "привет")
        XCTAssertEqual(DynamicKeyMapping.convert("привет", from: ru, to: us), "ghbdtn")
    }
}
