import XCTest
@testable import Glance

final class ThumbnailServiceTests: XCTestCase {
    func testWindowsHiddenByAFilteredSwitcherAreKept() {
        // ⌘` showed only window 1, but windows 2 and 3 still exist.
        let cache: [CGWindowID: String] = [1: "a", 2: "b", 3: "c"]
        let kept = ThumbnailService.pruned(cache, keeping: [1, 2, 3])
        XCTAssertEqual(kept, cache)
    }

    func testClosedWindowsAreDropped() {
        let cache: [CGWindowID: String] = [1: "a", 2: "b"]
        XCTAssertEqual(ThumbnailService.pruned(cache, keeping: [1]), [1: "a"])
    }
}
