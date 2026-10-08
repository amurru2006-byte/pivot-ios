import Foundation

struct TrainingAchievement: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case personalRecord, rank }
    var id: String
    var kind: Kind
    var sessionID: UUID
    var setID: UUID
    var exercise: String
    var value: Double
    var previousValue: Double?
    var benchmark: StrengthBenchmark?
    var rankLevel: Int?
    var createdAt: Date
    var presentedAt: Date? = nil
}

enum TrainingRecords {
    static func isAssisted(_ exercise: TrainingExercise) -> Bool {
        let key = EventCoalescer.normalized(exercise.name + " " + (exercise.catalogID ?? "") + " " + exercise.coachNotes)
        return key.contains("assisted") || key.contains("assistit") || key.contains("peso tolto")
    }
    static func maximum(_ set: TrainingSet, exercise: TrainingExercise) -> Double? {
        guard set.done, set.skipped != true, set.resolvedKind != .warmup, !exercise.usesDuration,
              !isAssisted(exercise), set.canComplete(exercise) else { return nil }
        return ExerciseProgress.estimatedMax(set)
    }
    static func previousMaximum(exercise: TrainingExercise, library: TrainingLibrary, through date: Date) -> Double? {
        library.sessions.filter { $0.start <= date }.flatMap(\.exercises)
            .filter { $0.skipped != true && sameExercise($0.exercise, exercise) }
            .flatMap { log in log.sets.compactMap { maximum($0, exercise: log.exercise) } }.max()
    }
    private static func sameExercise(_ lhs: TrainingExercise, _ rhs: TrainingExercise) -> Bool {
        if let a = lhs.catalogID, let b = rhs.catalogID { return a == b }
        return EventCoalescer.normalized(lhs.name) == EventCoalescer.normalized(rhs.name)
    }
    /// Called from the single persistence owner, for UI and widget alike. It
    /// only celebrates false→true completion transitions in a current workout.
    static func newAchievements(session: TrainingSession, previous: TrainingSession?, library: TrainingLibrary, profile: StrengthProfile?, now: Date = Date()) -> [TrainingAchievement] {
        guard session.end == nil else { return [] }
        var result: [TrainingAchievement] = [], comparison = library
        var existing = Set((library.achievements ?? []).map(\.id))
        // Compare against the persisted state, including more recent workouts
        // when an unfinished older workout is edited. Never compare a newly
        // completed set against itself, or duplicate a session during a batch.
        var persisted = previous ?? session
        if previous == nil {
            for ei in persisted.exercises.indices {
                for ti in persisted.exercises[ei].sets.indices { persisted.exercises[ei].sets[ti].done = false }
            }
        }
        comparison.sessions.removeAll { $0.id == session.id }
        comparison.sessions.append(persisted)
        for log in session.exercises where log.skipped != true {
            for set in log.sets {
                let wasDone = previous?.exercises.flatMap(\.sets).first { $0.id == set.id }?.done == true
                guard !wasDone, let value = maximum(set, exercise: log.exercise) else { continue }
                let old = previousMaximum(exercise: log.exercise, library: comparison, through: now)
                if let old, value > old + 0.01 {
                    let key = "pr:\(session.id):\(set.id):\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value))"
                    if existing.insert(key).inserted {
                        result.append(.init(id: key, kind: .personalRecord, sessionID: session.id, setID: set.id, exercise: log.exercise.name,
                                            value: value, previousValue: old, createdAt: now))
                    }
                }
                if let profile, let benchmark = StrengthBenchmark.resolve(log.exercise),
                   let rank = StrengthRanking.result(benchmark: benchmark, maximum: value, profile: profile, at: now) {
                    let earlier = StrengthRanking.bestMaximum(for: benchmark, library: comparison, before: now)
                        .flatMap { StrengthRanking.result(benchmark: benchmark, maximum: $0, profile: profile, at: now) }
                    let highWater = ((library.achievements ?? []) + result).filter { $0.kind == .rank && $0.benchmark == benchmark }.compactMap(\.rankLevel).max() ?? -1
                    if rank.level > max(earlier?.level ?? -1, highWater) {
                        let key = "rank:\(benchmark.rawValue):\(rank.level)"
                        if existing.insert(key).inserted {
                            result.append(.init(id: key, kind: .rank, sessionID: session.id, setID: set.id, exercise: log.exercise.name,
                                                value: value, previousValue: earlier?.estimatedMax, benchmark: benchmark, rankLevel: rank.level, createdAt: now))
                        }
                    }
                }
                // Multiple sets saved together compare to each preceding set,
                // not repeatedly to the same pre-save best.
                if let si = comparison.sessions.firstIndex(where: { $0.id == session.id }),
                   let ei = comparison.sessions[si].exercises.firstIndex(where: { $0.id == log.id }),
                   let ti = comparison.sessions[si].exercises[ei].sets.firstIndex(where: { $0.id == set.id }) {
                    comparison.sessions[si].exercises[ei].sets[ti] = set
                } else if let si = comparison.sessions.firstIndex(where: { $0.id == session.id }) {
                    if let ei = comparison.sessions[si].exercises.firstIndex(where: { $0.id == log.id }) {
                        comparison.sessions[si].exercises[ei].sets.append(set)
                    } else { comparison.sessions[si].exercises.append(.init(exercise: log.exercise, sets: [set])) }
                }
            }
        }
        return result
    }
    static func retainingHistory(_ achievements: [TrainingAchievement]) -> [TrainingAchievement] {
        let ranks = achievements.filter { $0.kind == .rank }
        return (ranks + achievements.filter { $0.kind == .personalRecord }.suffix(max(0, 500 - ranks.count)))
            .sorted { $0.createdAt < $1.createdAt }
    }
    static func isCurrent(_ achievement: TrainingAchievement, library: TrainingLibrary) -> Bool {
        guard let log = library.sessions.first(where: { $0.id == achievement.sessionID })?.exercises
            .first(where: { $0.sets.contains(where: { $0.id == achievement.setID }) }), log.skipped != true,
              let set = log.sets.first(where: { $0.id == achievement.setID }),
              let value = maximum(set, exercise: log.exercise) else { return false }
        return abs(value - achievement.value) < 0.01
    }
}
