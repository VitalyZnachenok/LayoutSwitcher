import XCTest
@testable import LayoutSwitcher

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("3.2", than: "3.1"))
        XCTAssertTrue(UpdateChecker.isNewer("3.10", than: "3.9"))
        XCTAssertTrue(UpdateChecker.isNewer("4.0", than: "3.99.9"))
        XCTAssertTrue(UpdateChecker.isNewer("v3.2", than: "3.1"))
        XCTAssertTrue(UpdateChecker.isNewer("3.1.1", than: "3.1"))
        XCTAssertFalse(UpdateChecker.isNewer("3.1", than: "3.1"))
        XCTAssertFalse(UpdateChecker.isNewer("3.1.0", than: "3.1"))
        XCTAssertFalse(UpdateChecker.isNewer("3.0", than: "3.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.9", than: "3.1"))
        XCTAssertFalse(UpdateChecker.isNewer("garbage", than: "3.1"))
    }
    
    func testNormalizedVersion() {
        XCTAssertEqual(UpdateChecker.normalizedVersion("v3.2"), "3.2")
        XCTAssertEqual(UpdateChecker.normalizedVersion(" V3.2\n"), "3.2")
        XCTAssertEqual(UpdateChecker.normalizedVersion("3.2"), "3.2")
    }
    
    func testParseGitHubRelease() throws {
        let json = """
        {"tag_name":"3.2","html_url":"https://github.com/VitalyZnachenok/LayoutSwitcher/releases/tag/3.2",
         "draft":false,"prerelease":false,
         "assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},
                   {"name":"LayoutSwitcher-3.2.dmg","browser_download_url":"https://example.com/LayoutSwitcher-3.2.dmg"}]}
        """.data(using: .utf8)!
        let release = try UpdateChecker.parseRelease(from: json)
        XCTAssertEqual(release.version, "3.2")
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://example.com/LayoutSwitcher-3.2.dmg")
        XCTAssertEqual(release.bestURL, release.downloadURL)
    }
    
    func testParseReleaseWithoutDMGFallsBackToPage() throws {
        let json = """
        {"tag_name":"v3.3","html_url":"https://github.com/VitalyZnachenok/LayoutSwitcher/releases/tag/3.3","assets":[]}
        """.data(using: .utf8)!
        let release = try UpdateChecker.parseRelease(from: json)
        XCTAssertEqual(release.version, "3.3")
        XCTAssertNil(release.downloadURL)
        XCTAssertEqual(release.bestURL, release.pageURL)
    }
}
