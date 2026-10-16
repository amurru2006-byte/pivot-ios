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
        for attempt in 0...maxSwipes {
            let screen = app.frame
            // XCTest exposes isHittable as an element property, not a
            // supported query-predicate key path.
            let navigation = app.navigationBars.allElementsBoundByIndex.first { $0.isHittable }
            let tabs = app.tabBars.firstMatch
            let recovery = app.descendants(matching: .any)["workout-recovery-bar"].firstMatch
            let keyboard = app.keyboards.firstMatch
            var top = screen.minY + 60
            var bottom = screen.maxY - 34
            if let navigation { top = max(top, navigation.frame.maxY) }
            // A presented sheet can leave the underlying tab bar in the AX
            // tree. It does not cover this sheet's controls.
            if tabs.exists && tabs.isHittable { bottom = min(bottom, tabs.frame.minY) }
            if recovery.exists && recovery.isHittable { bottom = min(bottom, recovery.frame.minY) }
            if keyboard.exists && keyboard.frame.height > 0 { bottom = min(bottom, keyboard.frame.minY) }
            let frame = element.exists ? element.frame : .zero
            let finite = frame.minY.isFinite && frame.maxY.isFinite && frame.height > 0
            if finite && frame.minY >= top + 8 && frame.maxY <= bottom - 8 && element.isHittable {
                return
            }
            if attempt == maxSwipes { break }
            // Form exposes a collection/table instead of a ScrollView. Find
            // the container owning the target, not a covered screen behind it.
            let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            let visible = containers.filter { $0.isHittable }
            let scroll: XCUIElement?
            if element.exists {
                let identifier = element.identifier, label = element.label, type = element.elementType
                scroll = visible.first { container in
                    if !identifier.isEmpty { return container.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists }
                    return container.descendants(matching: type).matching(NSPredicate(format: "label == %@", label)).firstMatch.exists
                } ?? visible.last
            } else { scroll = visible.last }
            if finite && frame.minY < top + 8 {
                if let scroll { scroll.swipeDown(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
            } else {
                if let scroll { scroll.swipeUp(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            }
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "unreachable-control-" + element.identifier
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Control never became fully visible: \(element.identifier), frame \(element.frame)", file: file, line: line)
    }
}
