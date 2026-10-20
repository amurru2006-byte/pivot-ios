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
        // A navigation bar is not itself an actionable control. iOS can
        // throw while computing its activation point during sheet changes.
        // Use the foremost visible bar's bounds; keep the target's real tap.
        // Capture immutable bounds once. Holding an index-bound navigation
        // element across a sheet animation can make index 1 disappear before
        // its next frame query, even when the destination is already visible.
        guard let root = try? app.snapshot() else {
            XCTFail("Cannot capture the current viewport", file: file, line: line); return
        }
        let screen = root.frame
        func flattened(_ snapshot: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            var result: [any XCUIElementSnapshot] = []
            var pending: [any XCUIElementSnapshot] = [snapshot]
            while let node = pending.popLast() {
                result.append(node); pending.append(contentsOf: node.children.reversed())
            }
            return result
        }
        var nodes = flattened(root)
        let navigationFrame = nodes.last { node in
            let bounds = node.frame
            guard node.elementType == .navigationBar else { return false }
            return bounds.minY.isFinite && bounds.maxY.isFinite && bounds.height > 0
                && bounds.width > 0 && bounds.intersects(screen)
        }?.frame
        let tabs = app.tabBars.firstMatch
        let recovery = app.descendants(matching: .any)["workout-recovery-bar"].firstMatch
        var top = screen.minY + 60
        var viewportBottom = screen.maxY - 34
        if let navigationFrame { top = max(top, navigationFrame.maxY) }
        // A presented sheet can leave the underlying tab bar in the AX
        // tree. It does not cover this sheet's controls.
        // The already captured snapshot proves absence without another remote
        // AX query. Keep live hittability checks for bars actually present:
        // a sheet may cover the underlying tab bar.
        if nodes.contains(where: { $0.elementType == .tabBar }), tabs.exists && tabs.isHittable {
            viewportBottom = min(viewportBottom, tabs.frame.minY)
        }
        if nodes.contains(where: { $0.identifier == "workout-recovery-bar" }), recovery.exists && recovery.isHittable {
            viewportBottom = min(viewportBottom, recovery.frame.minY)
        }
        var owningScroll: XCUIElement?
        for attempt in 0...maxSwipes {
            // Navigation/scroll ownership does not change when swiping this
            // screen. Avoid rediscovering the entire AX tree on every swipe.
            // Keyboard geometry must remain live: a swipe can dismiss it.
            if attempt > 0 {
                guard let refreshed = try? app.snapshot() else {
                    XCTFail("Cannot refresh the viewport after scrolling", file: file, line: line); return
                }
                nodes = flattened(refreshed)
            }
            var bottom = viewportBottom
            if let keyboard = nodes.last(where: { $0.elementType == .keyboard && $0.frame.height > 0 }) {
                bottom = min(bottom, keyboard.frame.minY)
            }
            let frame = element.exists ? element.frame : .zero
            let finite = frame.minY.isFinite && frame.maxY.isFinite && frame.height > 0
            if finite && frame.minY >= top + 8 && frame.maxY <= bottom - 8 && element.isHittable {
                return
            }
            if attempt == maxSwipes { break }
            // Form exposes a collection/table instead of a ScrollView. Find
            // the container owning the target, not a covered screen behind it.
            if owningScroll?.exists != true || owningScroll?.isHittable != true {
                let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
                let visible = containers.filter { $0.isHittable }
                if element.exists {
                    let identifier = element.identifier, label = element.label, type = element.elementType
                    owningScroll = visible.first { container in
                        if !identifier.isEmpty { return container.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists }
                        return container.descendants(matching: type).matching(NSPredicate(format: "label == %@", label)).firstMatch.exists
                    } ?? visible.last
                } else { owningScroll = visible.last }
            }
            if finite && frame.minY < top + 8 {
                if let owningScroll { owningScroll.swipeDown(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
            } else {
                if let owningScroll { owningScroll.swipeUp(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            }
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "unreachable-control-" + element.identifier
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Control never became fully visible: \(element.identifier), frame \(element.frame)", file: file, line: line)
    }
}
