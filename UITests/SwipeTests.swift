import XCTest

/// Swipes the Instagram page. Catches crashes in touch handling, like the one in 1.2 (5) where
/// the web view was created before the app finished launching and the first swipe crashed it.
final class SwipeTests: XCTestCase {
    func testSwipingDoesNotCrash() {
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        sleep(3)
        for i in 0..<10 {
            if i % 2 == 0 { web.swipeUp() } else { web.swipeDown() }
            XCTAssertEqual(app.state, .runningForeground, "App stopped after \(i + 1) swipes")
            if app.state != .runningForeground { return }
        }
    }
}
