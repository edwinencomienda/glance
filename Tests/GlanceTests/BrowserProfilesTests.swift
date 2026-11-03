import XCTest
@testable import Glance

final class BrowserProfilesTests: XCTestCase {
    func testOnlyProfileButtonClassesProduceLabels() {
        XCTAssertEqual(BrowserProfiles.label(classes: ["EdgeAvatarToolbarButton"], title: " Work "), "Work")
        XCTAssertEqual(BrowserProfiles.label(classes: ["AvatarToolbarButton"], title: "Personal"), "Personal")
        XCTAssertNil(BrowserProfiles.label(classes: ["ToolbarButton"], title: "Work"))
        XCTAssertNil(BrowserProfiles.label(classes: ["EdgeAvatarToolbarButton"], title: "  "))
        XCTAssertEqual(BrowserProfiles.label(classes: ["EdgeAvatarToolbarButton"], title: " Work Profile "), "Work")
        XCTAssertEqual(BrowserProfiles.label(classes: ["AvatarToolbarButton"], title: "Work Profile"), "Work Profile")
        XCTAssertEqual(BrowserProfiles.label(classes: ["EdgeAvatarToolbarButton"], title: "Profile"), "Profile")
    }

}
