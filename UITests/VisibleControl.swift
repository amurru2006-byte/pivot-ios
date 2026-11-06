import XCTest

extension XCTestCase {
    /// One real touch at the visible native thumb. Nested SwiftUI AX switch
    /// activation points can be stale even while both wrappers are hittable.
    /// Never retry the touch or set state through a fixture to make a test pass.
    func tapVisibleSwitchOnce(_ element: XCUIElement, to enabled: Bool, in app: XCUIApplication,
                              useAppCoordinates: Bool = false,
                              file: StaticString = #filePath, line: UInt = #line) {
        scrollControlIntoView(element, in: app, file: file, line: line)
        let before = enabled ? "0" : "1", after = enabled ? "1" : "0"
        guard element.value as? String == before, element.isEnabled, element.isHittable,
              let snapshot = try? element.snapshot() else {
            XCTFail("Switch must be visible, enabled and in its expected initial state", file: file, line: line); return
        }
        func flattened(_ value: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            var nodes: [any XCUIElementSnapshot] = [], pending: [any XCUIElementSnapshot] = [value]
            while let node = pending.popLast() { nodes.append(node); pending.append(contentsOf: node.children) }
            return nodes
        }
        let thumb: CGRect
        if useAppCoordinates {
            // Only the routing Form opts into app coordinates. Its targeted
            // snapshot can omit the native child; resolve that child from
            // the full app hierarchy without changing other controls' path.
            guard let appSnapshot = try? app.snapshot() else {
                XCTFail("Cannot capture the visible switch hierarchy", file: file, line: line); return
            }
            let wrappers = flattened(appSnapshot).filter {
                $0.elementType == snapshot.elementType && $0.identifier == snapshot.identifier
                    && $0.label == snapshot.label && $0.frame == snapshot.frame
            }
            guard wrappers.count == 1,
                  let native = flattened(wrappers[0]).filter({
                      $0.elementType == .switch && $0.frame.width > 0 && $0.frame.height > 0
                          && snapshot.frame.contains($0.frame)
                  }).min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })?.frame,
                  native.width <= native.height * 3,
                  snapshot.frame.width > 0, snapshot.frame.height > 0 else {
                XCTFail("Cannot locate the native switch thumb in the routing Form", file: file, line: line); return
            }
            thumb = native
        } else {
            // Preserve the previously verified element-relative touch for
            // ordinary controls and sheets. Their AX snapshots differ from
            // the routing Form and must not inherit its special lookup.
            var nodes: [any XCUIElementSnapshot] = [snapshot], pending = snapshot.children
            while let node = pending.popLast() { nodes.append(node); pending.append(contentsOf: node.children) }
            guard let native = nodes.last(where: { $0.elementType == .switch && $0.frame.width > 0 && $0.frame.height > 0 })?.frame,
                  snapshot.frame.width > 0, snapshot.frame.height > 0 else {
                XCTFail("Cannot locate the native switch thumb", file: file, line: line); return
            }
            thumb = native
        }
        let dx = (thumb.midX - snapshot.frame.minX) / snapshot.frame.width
        let dy = (thumb.midY - snapshot.frame.minY) / snapshot.frame.height
        guard dx.isFinite, dy.isFinite, (0...1).contains(dx), (0...1).contains(dy) else {
            XCTFail("Switch thumb is outside its visible wrapper", file: file, line: line); return
        }
        if useAppCoordinates {
            let screen = app.frame
            guard screen.contains(thumb) else {
                XCTFail("Native switch must be inside the current app viewport", file: file, line: line); return
            }
            // Opt-in only for the routing Form's wrapper. A sheet can use a
            // different app-coordinate origin; do not change other controls'
            // previously verified element-relative native thumb touch.
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: thumb.midX - screen.minX, dy: thumb.midY - screen.minY)).tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }
        let changed = expectation(for: NSPredicate(format: "value == %@", after), evaluatedWith: element)
        wait(for: [changed], timeout: 8)
        XCTAssertEqual(element.value as? String, after, file: file, line: line)
    }
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
        if let bar = nodes.last(where: { $0.elementType == .tabBar }), tabs.isHittable {
            viewportBottom = min(viewportBottom, bar.frame.minY)
        }
        if let bar = nodes.last(where: { $0.identifier == "workout-recovery-bar" }), recovery.isHittable {
            viewportBottom = min(viewportBottom, bar.frame.minY)
        }
        var owningScroll: XCUIElement?
        var diagnosticIdentifier = "unresolved-control"
        var lastFrame = CGRect.zero
        var previousVisibleFrame: CGRect?
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
            // One snapshot supplies existence and geometry together. Each AX
            // round trip costs seconds on the hosted simulator; do not ask
            // repeatedly for properties of the same unchanged element.
            let target = try? element.snapshot()
            let frame = target?.frame ?? .zero
            lastFrame = frame
            if let target, !target.identifier.isEmpty { diagnosticIdentifier = target.identifier }
            let finite = frame.minX.isFinite && frame.maxX.isFinite
                && frame.minY.isFinite && frame.maxY.isFinite
                && frame.width > 0 && frame.height > 0
            // Toolbar buttons belong inside the foremost navigation bar,
            // unlike scrolling content, which must remain below that bar.
            // Require actual AX ancestry as well as complete visible bounds.
            if finite, let target, let navigationFrame,
               let bar = nodes.last(where: { $0.elementType == .navigationBar && $0.frame == navigationFrame }),
               flattened(bar).contains(where: {
                   $0.elementType == target.elementType && $0.identifier == target.identifier
                       && $0.label == target.label && $0.frame == frame
               }), screen.contains(frame), navigationFrame.contains(frame), element.isHittable {
                return
            }
            if finite && screen.contains(frame) && frame.minY >= top + 8 && frame.maxY <= bottom - 8 {
                // A Form can materialize a row between the app snapshot and
                // its targeted snapshot after scrolling. Do not ask XCTest
                // for an activation point until both hierarchies agree and
                // the row keeps the same frame across two observations.
                // This waits for layout only: it never retries a touch or
                // replaces the live hittability check with geometry.
                let agrees = target.map { target in
                    nodes.contains {
                        $0.elementType == target.elementType && $0.identifier == target.identifier
                            && $0.label == target.label && $0.frame == frame
                    }
                } ?? false
                if agrees && previousVisibleFrame == frame {
                    if element.isHittable { return }
                } else {
                    previousVisibleFrame = agrees ? frame : nil
                    continue
                }
            }
            previousVisibleFrame = nil
            if attempt == maxSwipes { break }
            // Form exposes a collection/table instead of a ScrollView. Find
            // the container owning the target, not a covered screen behind it.
            if owningScroll?.exists != true || owningScroll?.isHittable != true {
                let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
                let visible = containers.filter { $0.isHittable }
                if let target {
                    let identifier = target.identifier, label = target.label, type = target.elementType
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
        // A missing target must not throw again while collecting diagnostics.
        // Keep the complete hierarchy and the original behavioural failure.
        hierarchy.name = "unreachable-control-" + diagnosticIdentifier
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Control never became fully visible: \(diagnosticIdentifier), last frame \(lastFrame)", file: file, line: line)
    }
}
