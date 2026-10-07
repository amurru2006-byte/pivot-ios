import Foundation

struct TrainingRest: Codable, Equatable {
    var exerciseID: String
    var setID: UUID
    var plannedSeconds: Int
    var startedAt: Date
    var deadline: Date?
    var remainingWhenPaused: Int? = nil
    init(exerciseID: String, setID: UUID, seconds: Int, now: Date = Date()) {
        self.exerciseID = exerciseID; self.setID = setID; plannedSeconds = seconds
        startedAt = now; deadline = now.addingTimeInterval(Double(seconds))
    }
    func remaining(at now: Date) -> Int { max(0, deadline.map { Int(ceil($0.timeIntervalSince(now))) } ?? remainingWhenPaused ?? 0) }
    func elapsed(at now: Date) -> Int { max(0, Int(now.timeIntervalSince(startedAt))) }
    mutating func togglePause(now: Date = Date()) {
        if deadline != nil {
            remainingWhenPaused = remaining(at: now); deadline = nil
        } else {
            deadline = now.addingTimeInterval(Double(remainingWhenPaused ?? 0)); remainingWhenPaused = nil
        }
    }
}

enum TrainingIsometry {
    static func isLegacy(_ log: TrainingExerciseLog, set: TrainingSet, tip: String = "") -> Bool {
        let notes = EventCoalescer.normalized(log.exercise.coachNotes + " " + log.notes + " " + tip)
        return EventCoalescer.normalized(log.exercise.name).contains("copenhagen")
            && notes.contains("kg sono secondi") && set.durationSeconds == nil && set.leftSeconds == nil && set.rightSeconds == nil
            && set.kg.map { $0.isFinite && $0 > 0 && $0 <= 86400 } == true && set.reps == 2
    }
    @discardableResult static func migrate(_ library: inout TrainingLibrary) -> Bool {
        var changed = false
        for si in library.sessions.indices {
            for ei in library.sessions[si].exercises.indices {
                var log = library.sessions[si].exercises[ei]
                for i in log.sets.indices where isLegacy(log, set: log.sets[i], tip: library.tips[log.id] ?? "") {
                    let old = log.sets[i]
                    log.sets[i].legacyKG = old.kg; log.sets[i].legacyReps = old.reps
                    log.sets[i].leftSeconds = Int(old.kg!.rounded()); log.sets[i].rightSeconds = Int(old.kg!.rounded())
                    log.sets[i].kg = nil; log.sets[i].reps = nil
                    log.exercise.isometric = true; log.exercise.separateSides = true; log.exercise.weightedHold = false
                    changed = true
                }
                library.sessions[si].exercises[ei] = log
            }
        }
        if changed {
            let ids = Set(library.sessions.flatMap(\.exercises).filter { $0.sets.contains { $0.legacyKG != nil } }.map(\.id))
            for pi in library.plans.indices {
                for di in library.plans[pi].payload.days.indices {
                    for ei in library.plans[pi].payload.days[di].exercises.indices where ids.contains(library.plans[pi].payload.days[di].exercises[ei].id) {
                        library.plans[pi].payload.days[di].exercises[ei].isometric = true
                        library.plans[pi].payload.days[di].exercises[ei].separateSides = true
                        library.plans[pi].payload.days[di].exercises[ei].weightedHold = false
                    }
                }
            }
        }
        return changed
    }
}

enum TrainingReports {
    static func week(containing date: Date) -> DateInterval { StudentPayments.week(containing: date) }
    static func performed(in interval: DateInterval, library: TrainingLibrary) -> [TrainingSession] {
        library.sessions.filter { $0.start >= interval.start && $0.start < interval.end && $0.exercises.contains { $0.sets.contains(where: \.done) } }.sorted { $0.start < $1.start }
    }
    static func performance(_ set: TrainingSet, exercise: TrainingExercise) -> String {
        if exercise.usesDuration {
            let duration = exercise.separateSides == true ? "Sx \(set.leftSeconds.map(String.init) ?? "-") s / Dx \(set.rightSeconds.map(String.init) ?? "-") s" : "\(set.durationSeconds.map(String.init) ?? "-") s"
            return duration + (exercise.weightedHold == true ? " · zavorra \(set.kg.map { $0.formatted() } ?? "-") kg" : "")
        }
        return "\(set.kg.map { $0.formatted() } ?? "-") kg x \(set.reps.map(String.init) ?? "-") Reps"
    }
}
