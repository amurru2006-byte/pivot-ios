import XCTest
@testable import PivotCore

final class StrengthProgressionTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!
    private var bench: TrainingExercise { .init(id: "bench", name: "Bench Press", sets: 2, reps: "6", restSeconds: 0, coachNotes: "") }
    private func profile(_ mass: Double = 75, birth: String = "2006-01-01T12:00:00Z") -> StrengthProfile {
        .init(birthDate: ISO8601DateFormatter().date(from: birth), bodyMassKG: mass, heightCM: 175, referenceSex: .male)
    }
    private func session(_ sets: [TrainingSet], start: Date? = nil) -> TrainingSession {
        .init(planID: UUID(), dayName: "Test", calendarEventID: nil, start: start ?? now, exercises: [.init(exercise: bench, sets: sets)])
    }
    func testBodyMassChangesRankAndHeightDoesNotInventAnAdjustment() throws {
        let light = try XCTUnwrap(StrengthRanking.result(benchmark: .bench, maximum: 100, profile: profile(40), at: now))
        let heavy = try XCTUnwrap(StrengthRanking.result(benchmark: .bench, maximum: 100, profile: profile(100), at: now))
        XCTAssertEqual(light.level, 6); XCTAssertNil(light.nextTargetKG)
        XCTAssertEqual(heavy.level, 0); XCTAssertEqual(heavy.nextTargetKG!, 119, accuracy: 0.001)
        var taller = profile(40); taller.heightCM = 200
        XCTAssertEqual(StrengthRanking.result(benchmark: .bench, maximum: 100, profile: taller, at: now), light)
    }
    func testPublishedTablesHaveAscendingDecilesAndSevenBands() throws {
        XCTAssertEqual(StrengthRanking.percentileFloors, [0,10,30,50,70,80,90])
        for sex in StrengthReferenceSex.allCases {
            for exercise in StrengthBenchmark.allCases {
                for ageGroup in 0..<5 {
                    let cutpoints = StrengthNorms2024.deciles(sex: sex, benchmark: exercise, ageGroup: ageGroup)
                    XCTAssertEqual(cutpoints.count, 9)
                    XCTAssertTrue(cutpoints.allSatisfy { $0 > 0 && $0.isFinite })
                    XCTAssertTrue(zip(cutpoints, cutpoints.dropFirst()).allSatisfy { $0.0 < $0.1 })
                }
            }
        }
        // Table 4 is authoritative here; the abstract reports 1.95 instead.
        XCTAssertEqual(StrengthNorms2024.deciles(sex: .male, benchmark: .bench, ageGroup: 1).last, 1.96)
        let boundary = try XCTUnwrap(StrengthRanking.result(benchmark: .bench, maximum: 1.96 * 75, profile: profile(), at: now))
        XCTAssertEqual(boundary.level, 6); XCTAssertEqual(boundary.percentileFloor, 90)
    }
    func testAgeCategoryAndMissingProfileAreHandledWithoutInventedData() throws {
        XCTAssertNil(StrengthRanking.result(benchmark: .bench, maximum: 100, profile: .init(), at: now))
        var invalid = profile(); invalid.bodyMassKG = .nan
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertNil(StrengthRanking.result(benchmark: .bench, maximum: 100, profile: invalid, at: now))
        let adolescent = profile(75, birth: "2009-01-01T12:00:00Z")
        let adult = profile(75, birth: "2008-01-01T12:00:00Z")
        XCTAssertEqual(StrengthRanking.result(benchmark: .bench, maximum: 75, profile: adolescent, at: now)?.level, 1)
        XCTAssertEqual(StrengthRanking.result(benchmark: .bench, maximum: 75, profile: adult, at: now)?.level, 0)
    }
    func testOnlyDocumentedMovementsAreRankedAndAssistanceIsExcluded() {
        XCTAssertEqual(StrengthBenchmark.resolve(bench), .bench)
        var ex = bench; ex.name = "Chest press machine"; XCTAssertNil(StrengthBenchmark.resolve(ex))
        ex.name = "Bench Press"; ex.catalogID = "unrelated-machine"; XCTAssertNil(StrengthBenchmark.resolve(ex))
        ex.catalogID = nil; ex.name = "Assisted Pull Up"
        XCTAssertNil(TrainingRecords.maximum(.init(number: 1, kg: 100, reps: 6, done: true), exercise: ex))
        ex.name = "Pull Up"; ex.coachNotes = "kg = peso tolto"; XCTAssertTrue(TrainingRecords.isAssisted(ex))
    }
    func testRecordsExcludeWarmupMissingSkippedIsometryAndHighRepEstimates() {
        let performed = TrainingSet(number: 1, kg: 60, reps: 6, done: true)
        XCTAssertEqual(TrainingRecords.maximum(performed, exercise: bench), 72)
        for excluded in [TrainingSet(number: 1, kg: 200, reps: 1, done: true, kind: .warmup),
                         TrainingSet(number: 1, kg: 60, reps: 11, done: true),
                         TrainingSet(number: 1, kg: 60, reps: 6, done: false),
                         TrainingSet(number: 1, kg: 60, reps: 6, done: true, skipped: true)] {
            XCTAssertNil(TrainingRecords.maximum(excluded, exercise: bench))
        }
        var iso = bench; iso.isometric = true
        XCTAssertNil(TrainingRecords.maximum(.init(number: 1, done: true, durationSeconds: 60), exercise: iso))
    }
    func testPRIsARealImprovementAndReopeningCannotRepeatTheSameCelebration() throws {
        var history = session([.init(number: 1, kg: 60, reps: 6, done: true)], start: now.addingTimeInterval(-86400))
        history.end = history.start.addingTimeInterval(100)
        let previous = session([.init(number: 1, kg: 65, reps: 6)])
        var current = previous; current.exercises[0].sets[0].done = true
        var library = TrainingLibrary(sessions: [history, previous])
        let earned = TrainingRecords.newAchievements(session: current, previous: previous, library: library, profile: nil, now: now)
        XCTAssertEqual(earned.count, 1); XCTAssertEqual(earned[0].value, 78); XCTAssertEqual(earned[0].previousValue, 72)
        library.achievements = earned
        XCTAssertTrue(TrainingRecords.newAchievements(session: current, previous: previous, library: library, profile: nil, now: now).isEmpty)
        XCTAssertTrue(TrainingRecords.isCurrent(earned[0], library: .init(sessions: [current])))
        XCTAssertFalse(TrainingRecords.isCurrent(earned[0], library: .init(sessions: [previous])))
        XCTAssertTrue(TrainingRecords.newAchievements(session: current, previous: previous, library: .init(sessions: [previous]), profile: nil, now: now).isEmpty)
    }
    func testEditingAnOlderUnfinishedWorkoutCannotBeatARealLaterRecord() {
        let previous = session([.init(number: 1, kg: 70, reps: 6)], start: now.addingTimeInterval(-86400))
        var current = previous; current.exercises[0].sets[0].done = true
        var later = session([.init(number: 1, kg: 80, reps: 6, done: true)], start: now.addingTimeInterval(-3600))
        later.end = later.start.addingTimeInterval(100)
        XCTAssertTrue(TrainingRecords.newAchievements(session: current, previous: previous, library: .init(sessions: [previous,later]), profile: profile(), now: now).isEmpty)
    }
    func testSameExerciseAcrossPlansStillUsesItsExistingRecord() {
        var history = session([.init(number: 1, kg: 80, reps: 6, done: true)], start: now.addingTimeInterval(-86400))
        history.end = history.start.addingTimeInterval(100); history.exercises[0].exercise.id = "old-plan-bench"
        let previous = session([.init(number: 1, kg: 60, reps: 6)])
        var current = previous; current.exercises[0].sets[0].done = true
        XCTAssertTrue(TrainingRecords.newAchievements(session: current, previous: previous, library: .init(sessions: [history,previous]), profile: nil, now: now).isEmpty)
    }
    func testBatchCompletionsUseEachPrecedingSetAndPersistOptionalMetadata() throws {
        let previous = session([.init(number: 1, kg: 100, reps: 6), .init(number: 2, kg: 50, reps: 6)])
        var current = previous; for i in current.exercises[0].sets.indices { current.exercises[0].sets[i].done = true }
        let earned = TrainingRecords.newAchievements(session: current, previous: previous, library: .init(sessions: [previous]), profile: profile(), now: now)
        XCTAssertEqual(earned.count, 1); XCTAssertEqual(earned[0].kind, .rank)
        var data = AppData(); data.strengthProfile = profile(); data.training = .init(sessions: [current], achievements: earned)
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.strengthProfile, data.strengthProfile); XCTAssertEqual(decoded.training?.achievements, earned)
        try decoded.training?.validate()
    }
    func testRankHighWaterSurvivesBoundedPRHistory() {
        let rank = TrainingAchievement(id: "rank:bench:6", kind: .rank, sessionID: UUID(), setID: UUID(), exercise: "Test", value: 200, benchmark: .bench, rankLevel: 6, createdAt: now)
        let records = (0..<550).map { i in TrainingAchievement(id: "pr:\(i)", kind: .personalRecord, sessionID: UUID(), setID: UUID(), exercise: "Test", value: 100, createdAt: now.addingTimeInterval(Double(i+1))) }
        let saved = TrainingRecords.retainingHistory([rank] + records)
        XCTAssertEqual(saved.count, 500); XCTAssertTrue(saved.contains(rank)); XCTAssertEqual(saved.last?.id, "pr:549")
    }
}
