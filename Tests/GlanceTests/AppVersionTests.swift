import XCTest
@testable import Glance

final class AppVersionTests: XCTestCase {
    func testParsesPlainAndTaggedVersions() {
        XCTAssertEqual(AppVersion("1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion("v10.0.12")?.description, "10.0.12")
    }

    func testRejectsMalformedVersions() {
        for bad in ["", "v", "1.2", "1.2.3.4", "1.2.x", "1..3", "v1.2.3-beta", " 1.2.3", "1.2.٣", "vv1.2.3"] {
            XCTAssertNil(AppVersion(bad), bad)
        }
    }

    func testComparesNumericallyNotAlphabetically() {
        XCTAssertLessThan(AppVersion("1.0.9")!, AppVersion("1.0.10")!)
        XCTAssertLessThan(AppVersion("1.9.0")!, AppVersion("1.10.0")!)
        XCTAssertLessThan(AppVersion("1.99.99")!, AppVersion("2.0.0")!)
        XCTAssertEqual(AppVersion("v1.0.3")!, AppVersion("1.0.3")!)
        XCTAssertFalse(AppVersion("1.0.3")! > AppVersion("1.0.3")!)
    }
}
