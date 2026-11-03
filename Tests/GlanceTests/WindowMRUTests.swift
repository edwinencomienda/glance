import XCTest
@testable import Glance

@MainActor
final class WindowMRUTests: XCTestCase {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, title: "\(id)", appName: "App", bounds: .zero, icon: nil)
    }

    func testRecentWindowOnAnotherSpaceComesSecond() {
        // You were watching a full-screen video (99), then switched to desktop window 1.
        let mru = WindowMRU()
        mru.touch(99)
        let order = mru.order(current: [window(1), window(2)], others: [window(99)])
        XCTAssertEqual(order.map(\.id), [1, 99, 2])
    }

    func testUnseenOtherSpaceWindowsGoLast() {
        let mru = WindowMRU()
        let order = mru.order(current: [window(1), window(2)], others: [window(7), window(8)])
        XCTAssertEqual(order.map(\.id), [1, 2, 7, 8])
    }

    func testCurrentSpaceZOrderWinsOverStaleStamps() {
        // Stamps say 2 is newer, but on screen 1 is in front of 2 and 3.
        let mru = WindowMRU()
        mru.touch(3)
        mru.touch(2)
        let order = mru.order(current: [window(1), window(3), window(2)], others: [])
        XCTAssertEqual(order.map(\.id), [1, 3, 2])
    }

    func testFromFullScreenVideoPreviousDesktopWindowIsSecond() {
        // On the video's Space: only the video is current; desktop windows are elsewhere.
        let mru = WindowMRU()
        mru.touch(2)
        mru.touch(1) // last desktop window used before going full screen
        let order = mru.order(current: [window(99)], others: [window(2), window(1), window(5)])
        XCTAssertEqual(order.map(\.id), [99, 1, 2, 5])
    }

    private func app(_ pid: pid_t) -> WindowInfo {
        var tile = WindowInfo(id: WindowInfo.appID(pid), pid: pid, title: "app \(pid)", appName: "App",
                              bounds: .zero, icon: nil)
        tile.isApp = true
        return tile
    }

    func testAppTilesFollowRecencyAndUnseenOnesGoLast() {
        // App 20 (now hidden) was used after window 7 on another Space; app 30 never was.
        let mru = WindowMRU()
        mru.touch(7)
        mru.touchApp(20)
        let order = mru.order(current: [window(1)], others: [window(7)], apps: [app(30), app(20)])
        XCTAssertEqual(order.map(\.id), [1, WindowInfo.appID(20), 7, WindowInfo.appID(30)])
    }

    func testAppStampSurvivesWhileItsTileIsntListed() {
        // An app's stamp must outlive orders where it has windows (no app tile).
        let mru = WindowMRU()
        mru.touchApp(20)
        _ = mru.order(current: [window(1)], others: [])
        let order = mru.order(current: [window(1)], others: [window(7)], apps: [app(20)])
        XCTAssertEqual(order.map(\.id), [1, WindowInfo.appID(20), 7])
    }

    func testAppIDsDontCollideWithWindowIDs() {
        XCTAssertGreaterThanOrEqual(WindowInfo.appID(1), 0x8000_0000)
        XCTAssertNotEqual(WindowInfo.appID(1), WindowInfo.appID(2))
    }
}
