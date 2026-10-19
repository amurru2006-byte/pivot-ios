import XCTest
@testable import PivotCore

final class CoachPremiumContextTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private func snapshot(_ data: AppData, purpose: String = "conversation") throws -> CoachV8Snapshot {
        try CoachV8Snapshot.make(message: "Continua", events: [], data: data, now: now, purpose: purpose, protocolVersion: 3)
    }
    private func fixture() -> AppData {
        var data = AppData()
        for index in 0..<2 {
            let time = now.addingTimeInterval(Double(index - 2) * 60)
            let user = CoachMessage(dayKey: PivotDate.key(now), role: .user, text: "Attività QA \(index)", createdAt: time, onlineHistoryEligible: true)
            let coach = CoachMessage(dayKey: user.dayKey, role: .coach, text: "Manca la fine", createdAt: time, onlineHistoryEligible: true)
            data.coachState.messages += [user, coach]
            let draft = CoachSavedCalendarDraft(messageID: coach.id, userMessageID: user.id, dayKey: user.dayKey,
                draft: .init(title: "Attività QA \(index)", start: now, end: nil, calendarHint: "Calendario QA", notes: "Nota QA", endEstimated: false),
                createdAt: time, updatedAt: time)
            data.coachState.calendarDrafts = (data.coachState.calendarDrafts ?? []) + [draft]
        }
        return data
    }
    func testOnlyExplicitlyEnabledActiveMemoriesAreSharedAndLegacyStaysLocal() throws {
        var data = AppData()
        data.coachState.memories = [
            .init(text: "Nota privata sanitaria QA", createdAt: now),
            .init(text: "Preferisco la sera", createdAt: now, onlineSharingAllowed: true),
            .init(text: "Scaduta", createdAt: now.addingTimeInterval(-120), expiresAt: now.addingTimeInterval(-60), onlineSharingAllowed: true),
            .init(text: "Futura", createdAt: now.addingTimeInterval(60), onlineSharingAllowed: true)
        ]
        let value = try snapshot(data)
        XCTAssertEqual(value.request.memories, ["Preferisco la sera"])
        XCTAssertFalse(String(decoding: value.encodedRequest, as: UTF8.self).contains("sanitaria"))
        XCTAssertEqual(data.coachState.memories.count, 4)
    }
    func testRewriteNeverIncludesEvenExplicitlySharedMemories() throws {
        var data = AppData(); data.coachState.memories = [.init(text: "Preferisco la sera", createdAt: now, onlineSharingAllowed: true)]
        XCTAssertTrue(try snapshot(data, purpose: "rewrite").request.memories.isEmpty)
    }
    func testSharedMemoriesUseSamePrivacyFilterAndNeverCalendarIDs() throws {
        var data = AppData()
        data.clients = [.init(name: "Persona Sintetica", rateCents: 1000)]
        data.coachState.memories = [.init(text: "Persona Sintetica scrive a prova@example.test", createdAt: now, onlineSharingAllowed: true)]
        XCTAssertEqual(try snapshot(data).request.memories, ["[contatto 1] scrive a [email]"])
    }
    func testLongMemoryCannotBeSharedOrSilentlyTruncated() throws {
        let memory = CoachMemory(text: String(repeating: "a", count: 241), createdAt: now, onlineSharingAllowed: true)
        XCTAssertFalse(memory.isValid)
        XCTAssertNotNil(CoachMemoryContext.problem(memory, replacing: nil, in: []))
        XCTAssertTrue(try CoachMemoryContext.online(memories: [memory], events: [], data: AppData(), now: now).isEmpty)
    }
    func testFourMemoryLimitAndReplacingOneAreExplicit() throws {
        let memories = (0..<4).map { CoachMemory(text: "Preferenza QA \($0)", createdAt: now, onlineSharingAllowed: true) }
        let fifth = CoachMemory(text: "Altra preferenza", createdAt: now, onlineSharingAllowed: true)
        XCTAssertNotNil(CoachMemoryContext.problem(fifth, replacing: nil, in: memories))
        XCTAssertNil(CoachMemoryContext.problem(memories[0], replacing: memories[0].id, in: memories))
        var data = AppData(); data.coachState.memories = memories + [fifth]
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        XCTAssertEqual(try CoachMemoryContext.online(memories: memories + [fifth], events: [], data: data, now: now).count, 4)
    }
    func testMemoryRevocationImmediatelyRemovesItFromNextSnapshot() throws {
        var data = AppData(); data.coachState.memories = [.init(text: "Preferisco la sera", createdAt: now, onlineSharingAllowed: true)]
        XCTAssertEqual(try snapshot(data).request.memories.count, 1)
        data.coachState.memories[0].onlineSharingAllowed = false
        XCTAssertTrue(try snapshot(data).request.memories.isEmpty)
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.coachState.memories[0].onlineSharingAllowed, false)
    }
    func testSharingAndExpiryRoundTripWithoutChangingLegacyDefaults() throws {
        var data = AppData(); data.coachState.memories = [.init(text: "QA", createdAt: now, expiresAt: now.addingTimeInterval(60), onlineSharingAllowed: true)]
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)).coachState.memories, data.coachState.memories)
        let legacy = try JSONDecoder().decode(CoachMemory.self, from: Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"QA\",\"createdAt\":0}".utf8))
        XCTAssertNil(legacy.onlineSharingAllowed)
    }
    func testExplicitFocusWinsOverLastDraftButDoesNotSendIDs() throws {
        var data = fixture(); let first = data.coachState.calendarDrafts![0]
        data.coachState.focusedCalendarDraftID = first.id
        let value = try snapshot(data)
        XCTAssertEqual(value.focusedDraft?.id, first.id)
        XCTAssertEqual(value.request.draftContext?.first?.title, first.draft.title)
        XCTAssertFalse(String(decoding: value.encodedRequest, as: UTF8.self).contains(first.id.uuidString))
    }
    func testEditingAnOldDraftDoesNotImplicitlyStealConversationFocus() throws {
        var data = fixture(); data.coachState.calendarDrafts?[0].updatedAt = now.addingTimeInterval(60)
        XCTAssertEqual(try snapshot(data).request.draftContext?.first?.title, "Attività QA 1")
        XCTAssertNil(try snapshot(data).focusedDraft)
    }
    func testStaleDeletedCreatedHealthAndUncertainFocusNeverFallsBackToAnotherDraft() throws {
        for state in ["missing", "created", "uncertain", "health", "yesterday"] {
            var data = fixture(); let first = data.coachState.calendarDrafts![0]
            data.coachState.focusedCalendarDraftID = first.id
            switch state {
            case "missing": data.coachState.calendarDrafts?.removeFirst()
            case "created": data.coachState.calendarDrafts?[0].createdEventID = "already-created"
            case "uncertain": data.coachState.calendarDrafts?[0].creationNeedsVerification = true
            case "health": data.coachState.messages[0].healthDerived = true
            default: data.coachState.calendarDrafts?[0].dayKey = "2026-10-18"
            }
            XCTAssertTrue(try snapshot(data).request.draftContext?.isEmpty == true, state)
            XCTAssertNil(try snapshot(data).focusedDraft, state)
        }
    }
    func testNewTopicOmitsOldStructuredDraftAndOldHistoryWithoutDeletingThem() throws {
        var data = fixture(); data.coachState.omitPreviousDraft = true; data.coachState.contextStartedAt = now
        data.coachState.messages.append(.init(dayKey: PivotDate.key(now), role: .user, text: "Nuova richiesta QA", createdAt: now, onlineHistoryEligible: true))
        let value = try snapshot(data)
        XCTAssertTrue(value.request.draftContext?.isEmpty == true)
        XCTAssertEqual(value.request.history.map(\.text), ["Nuova richiesta QA"])
        XCTAssertEqual(data.coachState.calendarDrafts?.count, 2); XCTAssertEqual(data.coachState.messages.count, 5)
    }
    func testFocusedPartialResponseRetainsKnownFieldsAndNotes() throws {
        let parent = fixture().coachState.calendarDrafts![0]
        let partial = CoachCalendarDraft(title: "", start: nil, end: now.addingTimeInterval(3600), calendarHint: nil, notes: "", endEstimated: false)
        let merged = CoachConversationFocus.continuing(partial, parent: parent)
        XCTAssertEqual(merged.title, parent.draft.title); XCTAssertEqual(merged.start, parent.draft.start)
        XCTAssertEqual(merged.end, partial.end); XCTAssertEqual(merged.notes, "Nota QA")
        XCTAssertEqual(merged.calendarHint, parent.draft.calendarHint)
    }
    func testDifferentTitleDoesNotInheritUnrelatedFacts() {
        let parent = fixture().coachState.calendarDrafts![0]
        let distinct = CoachCalendarDraft(title: "Altro evento QA", start: nil, end: nil, calendarHint: nil, notes: "", endEstimated: false)
        XCTAssertEqual(CoachConversationFocus.continuing(distinct, parent: parent), distinct)
    }
    func testChangedStartWithoutEndDoesNotInheritOldEndOrInventDuration() {
        var parent = fixture().coachState.calendarDrafts![0]; parent.draft.end = now.addingTimeInterval(3600)
        var draft = parent.draft; draft.start = now.addingTimeInterval(86400); draft.end = nil
        XCTAssertNil(CoachConversationFocus.continuing(draft, parent: parent).end)
    }
    func testCreationClearsFocusAndRoundTripKeepsNewTopicBoundary() throws {
        var data = fixture(); let first = data.coachState.calendarDrafts![0]
        data.coachState.focusedCalendarDraftID = first.id; data.coachState.contextStartedAt = now
        XCTAssertTrue(CoachDraftStore.markCreated(id: first.id, eventID: "saved-qa", calendarID: "calendar-qa", data: &data, now: now))
        XCTAssertNil(data.coachState.focusedCalendarDraftID)
        XCTAssertEqual(data.coachState.omitPreviousDraft, true)
        XCTAssertTrue(try snapshot(data).request.draftContext?.isEmpty == true, "Saving must not resurrect the other old pending draft")
        XCTAssertTrue(try snapshot(data).request.history.isEmpty)
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.coachState.contextStartedAt, now)
        XCTAssertEqual(restored.coachState.calendarDrafts?[0].createdEventID, "saved-qa")
    }
    func testEmojiAndPrivacyExpansionCannotBypassProviderMemoryLimit() throws {
        XCTAssertFalse(CoachMemory(text: String(repeating: "😀", count: 121), createdAt: now, onlineSharingAllowed: true).isValid)
        var data = AppData(); data.clients = [.init(name: "QA", rateCents: 1000)]
        // A short known name is not replaced; a longer one expands to an alias.
        data.clients[0].name = "Ana"
        data.coachState.memories = [.init(text: String(repeating: "Ana ", count: 60), createdAt: now, onlineSharingAllowed: true)]
        XCTAssertThrowsError(try snapshot(data), "Never silently truncate or omit the qualification of a shared preference") { error in
            guard case CoachV8Error.sharedMemoryTooLarge = error else { return XCTFail("Expected an actionable preference error, not a generic payload error") }
        }
    }
}
