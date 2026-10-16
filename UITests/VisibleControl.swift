import XCTest

extension XCTestCase {
    func attachFailureDiagnostics(_ name: String) {
        guard (testRun?.failureCount ?? 0) > 0 else { return }
        let app = XCUIApplication()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name + "-failure"; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    /// iOS 26 can report an off-screen or navigation-bar-covered SwiftUI control
    /// as hittable. Check real viewport geometry BEFORE querying hittability;
    /// keep the ordinary element tap and the caller's behavioural assertions.
    func scrollControlIntoView(_ element: XCUIElement, in app: XCUIApplication,
                               maxSwipes: Int = 15,
                               file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews.firstMatch
        for attempt in 0...maxSwipes {
            let screen = app.frame
            let navigation = app.navigationBars.firstMatch
            let tabs = app.tabBars.firstMatch
            let recovery = app.descendants(matching: .any)["workout-recovery-bar"].firstMatch
            var top = screen.minY + 60
            var bottom = screen.maxY - 34
            if navigation.exists { top = max(top, navigation.frame.maxY) }
            if tabs.exists { bottom = min(bottom, tabs.frame.minY) }
            if recovery.exists { bottom = min(bottom, recovery.frame.minY) }
            let frame = element.exists ? element.frame : .zero
            let finite = frame.minY.isFinite && frame.maxY.isFinite && frame.height > 0
            if finite && frame.minY >= top + 8 && frame.maxY <= bottom - 8 && element.isHittable {
                return
            }
            if attempt == maxSwipes { break }
            if finite && frame.minY < top + 8 {
                if scroll.exists { scroll.swipeDown(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
            } else {
                if scroll.exists { scroll.swipeUp(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            }
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "unreachable-control-" + element.identifier
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Control never became fully visible: \(element.identifier), frame \(element.frame)", file: file, line: line)
    }
}
