import XCTest
@testable import SyRtcSDK

/// 与 Android VideoFrameTrackerTest 相同的期望。
final class SyRtcVideoFrameTrackerTests: XCTestCase {
    func testFirstFrameThenOnlyChanges() {
        let t = SyRtcVideoFrameTracker()
        XCTAssertEqual(t.onFrame(width: 640, height: 360, rotation: 0), .init(first: true, sizeChanged: true))
        XCTAssertEqual(t.onFrame(width: 640, height: 360, rotation: 0), .init(first: false, sizeChanged: false))
        XCTAssertEqual(t.onFrame(width: 1280, height: 720, rotation: 0), .init(first: false, sizeChanged: true))
        XCTAssertEqual(t.onFrame(width: 1280, height: 720, rotation: 90), .init(first: false, sizeChanged: true))
        XCTAssertEqual(t.onFrame(width: 1280, height: 720, rotation: 90), .init(first: false, sizeChanged: false))
    }
}
