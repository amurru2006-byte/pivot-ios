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
    mutating func resetCountdown(now: Date = Date()) {
        // Reset the countdown, not the original start of the actual rest.
        deadline = now.addingTimeInterval(Double(plannedSeconds))
        remainingWhenPaused = nil
    }
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

enum TrainingSetEntry {
    static let noteLimit = 500

    static func note(_ text: String) -> String? {
        let value = String(text.prefix(noteLimit))
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private struct Position: Hashable {
        var kind: TrainingSetKind
        var additional: Bool
        var failure: Bool
    }

    private static func positions(_ log: TrainingExerciseLog) -> [Position: [TrainingSet]] {
        Dictionary(grouping: TrainingSetTemplate.markingOrigins(log.sets, prescribedWorkingSets: log.exercise.sets)) {
            Position(kind: $0.resolvedKind, additional: $0.isAdditional == true, failure: $0.reachesFailure)
        }
    }

    static func previousSets(for log: TrainingExerciseLog, session: TrainingSession, library: TrainingLibrary) -> [UUID: TrainingSet] {
        let current = positions(log)
        let earlier = library.sessions.filter { candidate in
            candidate.id != session.id && candidate.end.map { $0 <= session.start } == true
        }.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.id.uuidString < rhs.id.uuidString : lhs.start > rhs.start
        }
        var matches: [UUID: TrainingSet] = [:]
        for candidate in earlier {
            guard let old = candidate.exercises.first(where: {
                $0.skipped != true && TrainingRepProgression.sameIdentity($0.exercise, log.exercise)
                    && ($0.exercise.weightedHold == true) == (log.exercise.weightedHold == true)
            }) else { continue }
            let previous = positions(old)
            for (position, rows) in current {
                for (row, saved) in zip(rows, previous[position] ?? []) where matches[row.id] == nil && saved.done && saved.canComplete(old.exercise) {
                    matches[row.id] = saved
                }
            }
            if matches.count == log.sets.count { break }
        }
        return matches
    }

    struct Target {
        let label: String
        let quickReps: [Int]
    }

    static func target(for index: Int, in log: TrainingExerciseLog) -> Target? {
        let exercise = log.exercise
        guard log.sets.indices.contains(index), log.sets[index].resolvedKind != .warmup,
              log.sets[index].isAdditional != true else { return nil }
        let position = log.sets[..<index].filter { $0.resolvedKind != .warmup && $0.isAdditional != true }.count
        guard position < exercise.sets else { return nil }
        let target = prescribedValue(exercise.reps, position: position, count: exercise.sets)
        let simpleRange = target.flatMap(TrainingRepRange.init)
        let range = exercise.usesDuration ? nil : simpleRange
        let quick = range.flatMap { $0.upper - $0.lower < 5 ? Array($0.lower...$0.upper) : nil } ?? []
        let units = exercise.usesDuration ? "s" : "rip."
        var parts: [String] = []
        if let simpleRange {
            let count = simpleRange.lower == simpleRange.upper ? "\(simpleRange.lower)" : "\(simpleRange.lower)–\(simpleRange.upper)"
            parts.append("\(count) \(units)")
        } else if let target { parts.append(target) }
        // The existing private plan converter emits this exact label and
        // numbered fields. Free-form notes never become suggested weights.
        if let start = exercise.coachNotes.range(of: "Carico prescritto: "),
           let end = exercise.coachNotes[start.upperBound...].range(of: " kg."),
           let load = prescribedValue(String(exercise.coachNotes[start.upperBound..<end.lowerBound]), position: position, count: exercise.sets),
           load.range(of: #"^[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil,
           let kilograms = Double(load.replacingOccurrences(of: ",", with: ".")), (0...2000).contains(kilograms) {
            parts.append("\(load) kg")
        }
        return parts.isEmpty ? nil : Target(label: parts.joined(separator: " · "), quickReps: quick)
    }

    private static func prescribedValue(_ text: String, position: Int, count: Int) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "-", value != "—" else { return nil }
        if !value.hasPrefix("S1:") { return value }
        let entries = value.components(separatedBy: "; ")
        guard entries.count == count,
              entries.enumerated().allSatisfy({ $0.element.hasPrefix("S\($0.offset + 1): ") }) else { return nil }
        let selected = String(entries[position].dropFirst("S\(position + 1): ".count))
        return selected.isEmpty || ["-", "—"].contains(selected) ? nil : selected
    }

    static func usePrevious(_ previous: TrainingSet, at index: Int, in log: inout TrainingExerciseLog) {
        guard log.sets.indices.contains(index), !log.sets[index].isResolved,
              previous.resolvedKind == log.sets[index].resolvedKind, previous.reachesFailure == log.sets[index].reachesFailure,
              previous.done, previous.canComplete(log.exercise) else { return }
        var set = log.sets[index]
        if log.exercise.usesDuration {
            set.durationSeconds = previous.durationSeconds
            set.leftSeconds = previous.leftSeconds
            set.rightSeconds = previous.rightSeconds
            if log.exercise.weightedHold == true { set.kg = previous.kg }
        } else {
            set.kg = previous.kg
            set.reps = previous.reps
            if set.resolvedKind == .warmup {
                set.loadFraction = nil
                if let kg = set.kg, let workingLoad = TrainingSetTemplate.workingLoad(log.sets), kg / workingLoad <= 1.5 {
                    set.loadFraction = kg / workingLoad
                }
            }
        }
        log.sets[index] = set
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
