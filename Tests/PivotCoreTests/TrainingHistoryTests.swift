import XCTest
@testable import PivotCore

final class TrainingHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private var exercise: TrainingExercise { .init(id: "squat", name: "Barbell Squat", sets: 1, reps: "6", restSeconds: 60, coachNotes: "", catalogID: "Barbell_Squat") }
    private func plan() -> TrainingPlan {
        .init(payload: .init(formatVersion: 1, name: "PT", days: [
            .init(id: "squat", name: "Squat", exercises: [exercise]),
            .init(id: "bench", name: "Bench", exercises: [exercise])]))
    }
    private func workout(_ plan: TrainingPlan, day: Int = 0, kg: Double = 60, offset: Double = 0) -> TrainingSession {
        var session = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[day], eventID: nil, now: now.addingTimeInterval(offset))
        session.exercises[0].sets[0].kg = kg; session.exercises[0].sets[0].reps = 6
        session.exercises[0].sets[0].done = true; session.end = session.start.addingTimeInterval(600)
        session.updatedAt = session.end!
        return session
    }
    private func event() -> CalendarItem {
        .init(id: "linked", eventIdentifier: "event", calendarIdentifier: "calendar", calendarTitle: "Personale", title: "Palestra", start: now, end: now.addingTimeInterval(3600), location: "", notes: "", colorHex: "#123456", isAllDay: false, writable: true, kind: .workout)
    }
    func testDayHistoryUsesPlanAndStableDayIDNotExerciseOrName() {
        let plan = plan(), other = self.plan()
        var renamed = workout(plan); renamed.dayName = "Nome precedente"
        let bench = workout(plan, day: 1), wrongPlan = workout(other)
        let library = TrainingLibrary(plans: [plan, other], sessions: [bench, wrongPlan, renamed])
        XCTAssertEqual(TrainingHistory.sessions(planID: plan.id, dayID: "squat", dayName: "Squat", library: library).map(\.id), [renamed.id])
    }
    func testLegacyHistoryMatchesUnambiguousRevisionAndDoesNotMixNames() {
        var plan = plan(); let original = plan.payload
        plan.payload.days[0].name = "Squat nuovo"; plan.revisions = [.init(payload: original, date: now, note: "Nome")]
        var legacy = workout(plan); legacy.dayID = nil; legacy.dayName = " SQUAT "
        let library = TrainingLibrary(plans: [plan], sessions: [legacy])
        XCTAssertEqual(TrainingHistory.sessions(planID: plan.id, dayID: "squat", dayName: "Squat nuovo", library: library).count, 1)
        XCTAssertTrue(TrainingHistory.sessions(planID: plan.id, dayID: "bench", dayName: "Bench", library: library).isEmpty)
        plan.payload.days[1].name = "Squat"
        XCTAssertFalse(TrainingHistory.matches(legacy, planID: plan.id, dayID: "squat", dayName: "Squat nuovo", library: .init(plans: [plan])))
    }
    func testHistoryIncludesEmptyRunningSessionsAndHasNoTwentyItemLimit() {
        let plan = plan()
        var sessions = (0..<25).map { workout(plan, offset: Double($0 * 1000)) }
        sessions[24].end = nil; sessions[24].exercises[0].sets[0].done = false
        let result = TrainingHistory.sessions(planID: plan.id, dayID: "squat", dayName: "Squat", library: .init(plans: [plan], sessions: sessions))
        XCTAssertEqual(result.count, 25); XCTAssertEqual(result.first?.id, sessions[24].id)
        XCTAssertEqual(TrainingHistory.performedSets(sessions[24]), 0)
    }
    func testDeletionIsAtomicAndRejectsStaleOrRepeatedConfirmations() throws {
        let plan = plan(), saved = workout(plan)
        var data = AppData(); data.training = .init(plans: [plan], activePlanID: plan.id, sessions: [saved], tips: ["squat": "Tecnica"])
        var stale = saved; stale.notes = "Altra versione"
        XCTAssertThrowsError(try TrainingHistory.removing(stale, from: data))
        XCTAssertEqual(data.training?.sessions.first, saved)
        let removed = try TrainingHistory.removing(saved, from: data)
        XCTAssertTrue(removed.training!.sessions.isEmpty)
        XCTAssertEqual(removed.training?.plans.first?.payload, plan.payload); XCTAssertEqual(removed.training?.tips["squat"], "Tecnica")
        XCTAssertThrowsError(try TrainingHistory.removing(saved, from: removed))
    }
    func testDeletionClearsOnlyProvenWorkoutTimingPreservingDiaryAndCalendar() throws {
        let plan = plan(); var saved = workout(plan); saved.calendarEventID = "linked"
        var data = AppData(); data.training = .init(plans: [plan], sessions: [saved])
        var record = TrainingTiming.merging(saved, previous: nil, into: .init(id: "linked", snapshot: event()), now: now)
        record.notes = "Nota da conservare"; record.energy = 3; record.reflection = .init(result: "Bene")
        data.records[record.id] = record
        let result = try TrainingHistory.removing(saved, from: data)
        let retained = try XCTUnwrap(result.records["linked"])
        XCTAssertNil(retained.actualStart); XCTAssertNil(retained.actualEnd); XCTAssertNil(retained.trainingSessionID)
        XCTAssertEqual(retained.status, .pending); XCTAssertEqual(retained.activeMinutes, 0)
        XCTAssertEqual(retained.snapshot.start, event().start); XCTAssertEqual(retained.notes, record.notes)
        XCTAssertEqual(retained.energy, 3); XCTAssertEqual(retained.reflection?.result, "Bene")
    }
    func testDeletionPreservesManualAndLegacyDiaryTimes() throws {
        let plan = plan(); var saved = workout(plan); saved.calendarEventID = "linked"
        var data = AppData(); data.training = .init(plans: [plan], sessions: [saved])
        var record = TrainingTiming.merging(saved, previous: nil, into: .init(id: "linked", snapshot: event()))
        record.actualStart = now.addingTimeInterval(-100); data.records["linked"] = record
        let manual = try TrainingHistory.removing(saved, from: data)
        XCTAssertEqual(manual.records["linked"]?.actualStart, record.actualStart)
        XCTAssertEqual(manual.records["linked"]?.status, .completed)
        record.actualStart = saved.start; record.trainingSessionID = nil; data.records["linked"] = record
        let legacy = try TrainingHistory.removing(saved, from: data)
        XCTAssertEqual(legacy.records["linked"]?.actualStart, saved.start)
        XCTAssertEqual(legacy.records["linked"]?.status, .completed)
    }
    func testDeletingLinkedSessionFallsBackToRemainingSession() throws {
        let plan = plan(); var old = workout(plan, offset: -86400), latest = workout(plan)
        old.calendarEventID = "linked"; latest.calendarEventID = "linked"
        var data = AppData(); data.training = .init(plans: [plan], sessions: [old, latest])
        data.records["linked"] = TrainingTiming.merging(latest, previous: nil, into: .init(id: "linked", snapshot: event()))
        let result = try TrainingHistory.removing(latest, from: data)
        XCTAssertEqual(result.records["linked"]?.trainingSessionID, old.id)
        XCTAssertEqual(result.records["linked"]?.actualStart, old.start)
    }
    func testCorrectionRecalculatesPRValueAndDoesNotCreatePopups() throws {
        let plan = plan(), old = workout(plan, kg: 40, offset: -86400)
        var latest = workout(plan, kg: 60); latest.end = nil
        let earned = TrainingRecords.newAchievements(session: latest, previous: nil, library: .init(sessions: [old]), profile: nil, now: now)
        XCTAssertEqual(earned.count, 1)
        latest.end = now.addingTimeInterval(600); latest.exercises[0].sets[0].kg = 50
        let library = TrainingLibrary(sessions: [old, latest], achievements: earned)
        let corrected = try XCTUnwrap(TrainingRecords.reconciled(library: library, profile: nil, now: now)?.first)
        XCTAssertEqual(corrected.value, 60); XCTAssertEqual(corrected.previousValue, 48)
        XCTAssertNotNil(corrected.presentedAt); XCTAssertNotEqual(corrected.id, earned[0].id)
        XCTAssertTrue(TrainingRecords.isCurrent(corrected, library: library))
        latest.exercises[0].sets[0].kg = 30
        XCTAssertTrue(TrainingRecords.reconciled(library: .init(sessions: [old, latest], achievements: earned), profile: nil)!.isEmpty)
    }
    func testCorrectingEarlierWorkoutInvalidatesLaterPR() {
        let plan = plan(); var old = workout(plan, kg: 40, offset: -86400), latest = workout(plan, kg: 60)
        latest.end = nil
        let earned = TrainingRecords.newAchievements(session: latest, previous: nil, library: .init(sessions: [old]), profile: nil, now: now)
        old.exercises[0].sets[0].kg = 80
        XCTAssertTrue(TrainingRecords.reconciled(library: .init(sessions: [old, latest], achievements: earned), profile: nil)!.isEmpty)
    }
    func testDeletingPeakRemovesMedalsAndUpdatesProgressRankAndNextLoad() throws {
        let plan = plan(), old = workout(plan, kg: 40, offset: -86400)
        var peak = workout(plan, kg: 200); peak.end = nil
        let profile = StrengthProfile(birthDate: now.addingTimeInterval(-25 * 365.25 * 86400), bodyMassKG: 75, referenceSex: .male)
        let earned = TrainingRecords.newAchievements(session: peak, previous: nil, library: .init(sessions: [old]), profile: profile, now: now)
        XCTAssertTrue(earned.contains { $0.kind == .rank && $0.rankLevel == 6 })
        peak.end = now.addingTimeInterval(600)
        var data = AppData(); data.strengthProfile = profile
        data.training = .init(plans: [plan], sessions: [old, peak], achievements: earned)
        let result = try TrainingHistory.removing(peak, from: data)
        let library = try XCTUnwrap(result.training)
        XCTAssertTrue(library.achievements!.isEmpty)
        XCTAssertEqual(ExerciseProgress.calculate(exerciseID: "squat", library: library).bestLoad, 40)
        XCTAssertEqual(StrengthRanking.bestMaximum(for: .squat, library: library, before: now), 48)
        XCTAssertEqual(library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now).exercises[0].sets[0].kg, 40)
    }
    func testCorrectedRankUsesActualLoadAndInvalidWorkCannotKeepMedal() {
        let plan = plan()
        var peak = workout(plan, kg: 200); peak.end = nil
        let profile = StrengthProfile(birthDate: now.addingTimeInterval(-25 * 365.25 * 86400), bodyMassKG: 75, referenceSex: .male)
        let earned = TrainingRecords.newAchievements(session: peak, previous: nil, library: .init(), profile: profile, now: now)
        peak.exercises[0].sets[0].kg = 40
        let corrected = TrainingRecords.reconciled(library: .init(sessions: [peak], achievements: earned), profile: profile, now: now)
        XCTAssertEqual(corrected?.first?.rankLevel, 0); XCTAssertEqual(corrected?.first?.value, 48)
        peak.exercises[0].sets[0].kind = .warmup
        XCTAssertTrue(TrainingRecords.reconciled(library: .init(sessions: [peak], achievements: earned), profile: profile)!.isEmpty)
        peak.exercises[0].sets[0].kind = .working; peak.exercises[0].sets[0].done = false
        XCTAssertTrue(TrainingRecords.reconciled(library: .init(sessions: [peak], achievements: earned), profile: profile)!.isEmpty)
    }
    func testLegacyRecordCodableAndDeletedHistoryRoundTrip() throws {
        let record = EventRecord(id: "linked", snapshot: event())
        let decoded = try JSONDecoder().decode(EventRecord.self, from: JSONEncoder().encode(record))
        XCTAssertNil(decoded.trainingSessionID)
        let plan = plan(), session = workout(plan)
        var data = AppData(); data.training = .init(plans: [plan], sessions: [session])
        let removed = try TrainingHistory.removing(session, from: data)
        let backup = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(removed))
        XCTAssertTrue(backup.training!.sessions.isEmpty); XCTAssertEqual(backup.training?.plans.first?.payload, plan.payload)
    }
}
