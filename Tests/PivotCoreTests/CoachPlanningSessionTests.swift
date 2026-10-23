import XCTest
@testable import PivotCore

final class CoachPlanningSessionTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private var target: CalendarItem {
        .init(id: "session-target-qa", eventIdentifier: "native-target-qa", calendarIdentifier: "calendar-qa", calendarTitle: "Account QA",
            title: "Titolo privato sessione QA", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600),
            location: "Indirizzo privato sessione QA", notes: "Note private sessione QA", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
    }
    private var data: AppData {
        var value = AppData(); value.updatedAt = now
        value.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true)
        return value
    }
    private func intent(alias: String = "e0", allowed: [Int] = [1], excluded: [Int] = [2]) -> CoachPlanningIntent {
        .init(eventIDs: [alias], allowedDayOffsets: allowed, excludedDayOffsets: excluded,
            band: .afternoon, earliestMinute: nil, latestMinute: nil, afterEventID: nil)
    }
    private func snapshot(data: AppData, events: [CalendarItem]? = nil, at date: Date? = nil) throws -> CoachV8Snapshot {
        try CoachV8Snapshot.make(message: "Continuiamo il recupero QA", events: events ?? [target], data: data, now: date ?? now,
            purpose: "conversation", protocolVersion: 4, calendarScope: .week)
    }
    private func session(_ snapshot: CoachV8Snapshot, data: AppData, intent: CoachPlanningIntent? = nil,
                         at date: Date? = nil, events: [CalendarItem]? = nil) throws -> CoachPlanningSession {
        let response = CoachV8Response(version: 4, requestID: snapshot.request.requestID, mode: .recover, eventIDs: [],
            reply: "Da controllare", actions: [], planning: intent ?? self.intent())
        return try .make(response, snapshot: snapshot, messageID: UUID(), userMessageID: UUID(),
            access: .init(calendar: true, online: true), events: events ?? [target], data: data, now: date ?? now)
    }
    private func append(_ value: CoachPlanningSession, to data: inout AppData) throws {
        data.coachState.messages += [
            .init(id: value.userMessageID, dayKey: value.dayKey, role: .user, text: "Richiesta QA", createdAt: value.anchor, onlineHistoryEligible: true),
            .init(id: value.messageID, dayKey: value.dayKey, role: .coach, text: "Piano locale da controllare", createdAt: value.updatedAt, onlineHistoryEligible: false)
        ]
        var coach = data.coachState; try CoachPlanningStore.save(value, in: &coach); data.coachState = coach
    }
    private func saved() throws -> (CoachPlanningSession, AppData) {
        var value = data; let initial = try session(snapshot(data: value), data: value)
        try append(initial, to: &value); return (initial, value)
    }
    func testSessionKeepsOnlyNeededLocalBindingsAndSurvivesBackupWithoutChangingMoney() throws {
        let (initial, data) = try saved()
        XCTAssertTrue(initial.isValid); XCTAssertEqual(initial.bindings.count, 1)
        XCTAssertEqual(initial.sourceTitles, target.title); XCTAssertTrue(CoachPlanningStore.valid(data.coachState))
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.coachState.planningSessions, [initial])
        XCTAssertEqual(restored.coachState.focusedPlanningSessionID, initial.id)
        XCTAssertTrue(restored.moves.isEmpty); XCTAssertTrue(restored.payments.isEmpty); XCTAssertTrue(restored.income.isEmpty)
    }
    func testFreshSnapshotRemapsAliasesButNeverSendsNativeBindings() throws {
        let (_, data) = try saved()
        var earlier = target; earlier.id = "earlier-qa"; earlier.eventIdentifier = "earlier-native-qa"
        earlier.start.addTimeInterval(-7200); earlier.end.addTimeInterval(-7200); earlier.title = "Altro titolo QA"
        let value = try snapshot(data: data, events: [earlier, target])
        XCTAssertEqual(value.request.planningContext?.first?.intent.eventIDs, ["e1"])
        XCTAssertEqual(value.request.planningContext?.first?.anchor, now)
        let raw = String(decoding: value.encodedRequest, as: UTF8.self)
        for secret in [target.id, target.eventIdentifier, target.calendarIdentifier, target.title, target.location, target.notes, "bindings", "protectedExcludedDays"] {
            XCTAssertFalse(raw.contains(secret))
        }
        XCTAssertTrue(value.additionalPlanningSourceIDs.isEmpty)
    }
    func testMidnightKeepsOriginalAnchorAndDisclosesOnlyBoundSourceOutsideScope() throws {
        let (_, data) = try saved(), tomorrow = now.addingTimeInterval(86400)
        let value = try snapshot(data: data, at: tomorrow)
        let context = try XCTUnwrap(value.request.planningContext?.first)
        XCTAssertEqual(context.anchor, now); XCTAssertEqual(context.intent.allowedDayOffsets, [1])
        XCTAssertEqual(value.additionalPlanningSourceIDs, [target.id])
        XCTAssertEqual(value.request.events.count, 1)
        XCTAssertEqual(try context.intent.intervals(knownAliases: ["e0"], anchor: context.anchor, now: tomorrow).first?.start,
            PivotDate.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow))
    }
    func testContinuationRetainsSessionIdentityAndAbsoluteExclusionsEvenIfModelOmitsThem() throws {
        let (initial, data) = try saved(), tomorrow = now.addingTimeInterval(86400)
        let snap = try snapshot(data: data, at: tomorrow)
        let updated = try session(snap, data: data, intent: intent(allowed: [2], excluded: []), at: tomorrow)
        XCTAssertEqual(updated.id, initial.id); XCTAssertEqual(updated.createdAt, initial.createdAt)
        XCTAssertEqual(updated.anchor, tomorrow); XCTAssertEqual(updated.intent.allowedDayOffsets, [2])
        XCTAssertEqual(updated.intent.excludedDayOffsets, [1], "Wednesday stays excluded; it does not turn into Thursday after midnight")
        XCTAssertTrue(updated.pendingReadmittedDays.isEmpty)
    }
    func testPreviouslyExcludedDayRequiresExplicitNativeReviewBeforeAnotherCloudContext() throws {
        let (_, data) = try saved()
        let snap = try snapshot(data: data)
        var updated = try session(snap, data: data, intent: intent(allowed: [2], excluded: []))
        XCTAssertEqual(updated.pendingReadmittedDays, updated.allowedDays)
        XCTAssertThrowsError(try updated.context(remapping: snap.sources, now: now)) { error in
            XCTAssertEqual(error as? CoachPlanningSession.Failure, .reviewRequired)
        }
        try updated.confirmReadmittedDays(now: now)
        XCTAssertTrue(updated.pendingReadmittedDays.isEmpty)
        XCTAssertEqual(try updated.context(remapping: snap.sources, now: now).intent.allowedDayOffsets, [2])
    }
    func testExternalChangesOrDuplicateOccurrencesCannotBecomeFreshCloudContext() throws {
        let (_, data) = try saved()
        var changed = target; changed.location = "Nuova destinazione QA"
        for events in [[changed], [], [target, target]] {
            // Duplicate coalescing is tested directly on the bound provenance,
            // not bypassed by choosing whichever copy happens to sort first.
            let initial = try XCTUnwrap(data.coachState.planningSessions?.first)
            XCTAssertThrowsError(try initial.boundEvents(in: events, now: now)) { error in
                XCTAssertEqual(error as? CoachPlanningSession.Failure, .changed)
            }
        }
        XCTAssertThrowsError(try snapshot(data: data, events: [changed]))
    }
    func testExpiredPlanDoesNotShiftOldDatesToANewWeekOrPreventExplicitNewTopic() throws {
        let (initial, data) = try saved(), nextWeek = now.addingTimeInterval(7 * 86400)
        XCTAssertFalse(initial.isActive(at: nextWeek))
        XCTAssertThrowsError(try snapshot(data: data, at: nextWeek)) { error in
            XCTAssertEqual(error as? CoachPlanningSession.Failure, .expired)
        }
        var fresh = data; fresh.coachState.focusedPlanningSessionID = nil
        XCTAssertEqual(try snapshot(data: fresh, at: nextWeek).request.planningContext, [])
        XCTAssertEqual(fresh.coachState.planningSessions, [initial])
    }
    func testNewTargetDoesNotOverwriteOrInheritAnUnrelatedOldPlan() throws {
        let (initial, data) = try saved()
        var other = target; other.id = "other-qa"; other.eventIdentifier = "other-native-qa"
        other.start.addTimeInterval(7200); other.end.addTimeInterval(7200)
        var current = data; current.rules[other.id] = current.rules[target.id]
        let snap = try snapshot(data: current, events: [target, other])
        let alias = try XCTUnwrap(snap.sources.first { $0.value.id == other.id }?.key)
        let value = try session(snap, data: current, intent: intent(alias: alias, allowed: [3], excluded: []), events: [target, other])
        XCTAssertNotEqual(value.id, initial.id); XCTAssertTrue(value.protectedExcludedDays.isEmpty)
    }
    func testBackupRejectsMissingProvenanceHealthDerivedOriginAndDanglingFocus() throws {
        let (_, data) = try saved()
        var broken = data; broken.coachState.messages = []
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(broken)))
        broken = data; broken.coachState.focusedPlanningSessionID = UUID()
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(broken)))
        broken = data
        let id = try XCTUnwrap(broken.coachState.planningSessions?.first?.userMessageID)
        broken.coachState.messages = broken.coachState.messages.map { item in
            var item = item; if item.id == id { item.healthDerived = true }; return item
        }
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(broken)))
    }
    func testInvalidSaveLeavesExistingStateUntouched() throws {
        let (initial, data) = try saved(); var coach = data.coachState
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(coach)
        var invalid = initial; invalid.bindings = [:]
        XCTAssertThrowsError(try CoachPlanningStore.save(invalid, in: &coach))
        XCTAssertEqual(try encoder.encode(coach), before)
    }
    func testReadOnlyReferenceRemainsUsableWithoutGrantingWriteAccess() throws {
        var reference = target; reference.id = "reference-qa"; reference.eventIdentifier = "reference-native-qa"
        reference.start.addTimeInterval(-7200); reference.end.addTimeInterval(-7200); reference.writable = false; reference.kind = .meal
        let appData = data, events = [reference, target], snap = try snapshot(data: appData, events: events)
        var value = intent(alias: "e1"); value.afterEventID = "e0"
        let initial = try session(snap, data: appData, intent: value, events: events)
        XCTAssertTrue(initial.isValid)
        XCTAssertEqual(try initial.boundEvents(in: events, now: now).count, 2)
        XCTAssertEqual(try initial.context(remapping: snap.sources, now: now).intent.afterEventID, "e0")
        XCTAssertFalse(reference.writable)
    }
    func testAutumnTimeChangeKeepsOriginalCivilDayNotTwentyFourHourOffsets() throws {
        let formatter = ISO8601DateFormatter()
        let before = try XCTUnwrap(formatter.date(from: "2026-10-24T12:00:00+02:00"))
        let after = try XCTUnwrap(formatter.date(from: "2026-10-25T12:00:00+01:00"))
        var source = target; source.start = before.addingTimeInterval(-7200); source.end = before.addingTimeInterval(-3600)
        var appData = data; appData.updatedAt = before
        let first = try snapshot(data: appData, events: [source], at: before)
        let initial = try session(first, data: appData, at: before, events: [source])
        try append(initial, to: &appData)
        let next = try snapshot(data: appData, events: [source], at: after)
        let context = try XCTUnwrap(next.request.planningContext?.first)
        XCTAssertEqual(context.anchor, before)
        XCTAssertEqual(try context.intent.intervals(knownAliases: ["e0"], anchor: context.anchor, now: after).first?.start, after)
        XCTAssertEqual(next.additionalPlanningSourceIDs, [source.id])
    }
    func testOldBackupWithoutPlanningSessionsStillDecodes() throws {
        let value = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertNil(value.coachState.planningSessions); XCTAssertNil(value.coachState.focusedPlanningSessionID)
    }
    func testExpandedSourcePermissionIsEphemeralSpecificAndRevocable() {
        var permission = CoachConversationPermission()
        let day = PivotDate.key(now)
        permission.authorize(dayKey: day)
        XCTAssertFalse(permission.allowsPlanningSources([target.id], dayKey: day))
        permission.authorizePlanningSources([target.id], dayKey: day)
        XCTAssertTrue(permission.allowsPlanningSources([target.id], dayKey: day))
        XCTAssertFalse(permission.allowsPlanningSources(["another-qa"], dayKey: day))
        permission.revoke(); XCTAssertFalse(permission.allowsPlanningSources([target.id], dayKey: day))
        permission.authorize(dayKey: day); permission.authorizePlanningSources([target.id], dayKey: day)
        permission.authorize(dayKey: "2026-10-20")
        XCTAssertFalse(permission.allowsPlanningSources([target.id], dayKey: "2026-10-20"))
    }
}
