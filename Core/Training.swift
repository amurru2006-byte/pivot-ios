import Foundation

struct TrainingExercise: Codable, Identifiable, Equatable {
    // Stable across later plans so last performance and personal tips survive an import.
    var id: String
    var name: String
    var sets: Int
    var reps: String
    var restSeconds: Int
    var coachNotes: String
    var catalogID: String? = nil
    var isometric: Bool? = nil
    var separateSides: Bool? = nil
    var weightedHold: Bool? = nil
    var usesDuration: Bool {
        if let isometric { return isometric }
        let key = EventCoalescer.normalized(name)
        return key.contains("plank") || key == "wall sit" || key == "sedia al muro"
    }
    var isValid: Bool {
        !id.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...30).contains(sets) && (0...3600).contains(restSeconds)
    }
}

struct TrainingDay: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var exercises: [TrainingExercise]
}

struct TrainingPlanPayload: Codable, Equatable {
    var formatVersion: Int
    var name: String
    var days: [TrainingDay]
    func validate() throws {
        guard formatVersion == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...14).contains(days.count), Set(days.map(\.id)).count == days.count else { throw TrainingError.invalidPlan }
        for day in days {
            guard !day.id.isEmpty, !day.name.isEmpty, (1...40).contains(day.exercises.count),
                  Set(day.exercises.map(\.id)).count == day.exercises.count else { throw TrainingError.invalidPlan }
            for exercise in day.exercises {
                guard exercise.isValid else { throw TrainingError.invalidPlan }
            }
        }
    }
}

enum TrainingDayOrder {
    /// The first Pivot training PDF stored this specific three-day plan in
    /// alphabetical order. Keep every other plan exactly as authored.
    static func corrected(_ days: [TrainingDay]) -> [TrainingDay] {
        let names = days.map { EventCoalescer.normalized($0.name) }
        guard names == ["bench", "deadlift", "squat"] else { return days }
        return [days[2], days[0], days[1]]
    }
    static func corrected(_ payload: TrainingPlanPayload) -> TrainingPlanPayload {
        var result = payload
        result.days = corrected(payload.days)
        return result
    }
}

struct TrainingPlan: Codable, Identifiable {
    var id = UUID()
    var payload: TrainingPlanPayload
    var document: StudyDocument?
    var importedAt = Date()
    var revisions: [TrainingPlanRevision]? = nil
}

struct TrainingPlanRevision: Codable, Identifiable {
    var id = UUID()
    var payload: TrainingPlanPayload
    var date: Date
    var note: String
}

enum TrainingSetKind: String, Codable, CaseIterable, Identifiable {
    case warmup, working, backoff, superset, dropSet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .warmup: return "Riscaldamento"
        case .working: return "Allenante"
        case .backoff: return "Back-off"
        case .superset: return "Superset"
        case .dropSet: return "Drop set"
        }
    }
}

struct TrainingSet: Codable, Identifiable, Equatable {
    var id = UUID()
    var number: Int
    var kg: Double? = nil
    var reps: Int? = nil
    var done = false
    // Optional fields preserve every backup created before 0.7.4.
    var kind: TrainingSetKind? = nil
    var toFailure: Bool? = nil
    var supersetGroup: String? = nil
    // Warm-up load divided by the working load. It lets the same warm-up
    // structure follow a manually changed working weight next time.
    var loadFraction: Double? = nil
    var durationSeconds: Int? = nil
    var leftSeconds: Int? = nil
    var rightSeconds: Int? = nil
    var restSeconds: Int? = nil
    var actualRestSeconds: Int? = nil
    var completedAt: Date? = nil
    var legacyKG: Double? = nil
    var legacyReps: Int? = nil
    func canComplete(_ exercise: TrainingExercise) -> Bool {
        if exercise.usesDuration {
            let valid = exercise.separateSides == true ? (leftSeconds ?? 0) > 0 && (rightSeconds ?? 0) > 0 : (durationSeconds ?? 0) > 0
            return valid && (exercise.weightedHold != true || (kg.map { $0.isFinite && $0 >= 0 } ?? false))
        }
        return kg.map { $0.isFinite && $0 >= 0 } == true && (reps ?? 0) > 0
    }
    var holdTotal: Int { (durationSeconds ?? 0) + (leftSeconds ?? 0) + (rightSeconds ?? 0) }
    var resolvedKind: TrainingSetKind { kind ?? .working }
    var reachesFailure: Bool { toFailure == true }
}

enum TrainingSetTemplate {
    static func workingLoad(_ sets: [TrainingSet]) -> Double? {
        sets.filter { [.working, .superset].contains($0.resolvedKind) }
            .compactMap(\.kg).filter { $0.isFinite && $0 > 0 }.max()
    }
    static func next(previous: TrainingExerciseLog?, prescribedWorkingSets: Int) -> [TrainingSet] {
        guard let previous else {
            return (1...prescribedWorkingSets).map { TrainingSet(number: $0, kind: .working) }
        }
        // Only work actually performed becomes the next session's suggested
        // load.  We still preserve the manually arranged set types, but an
        // abandoned or half-filled set must not silently become history.
        let oldTarget = workingLoad(previous.sets.filter(\.done))
        var result = previous.sets.enumerated().map { offset, old -> TrainingSet in
            var fraction = old.done ? old.loadFraction : nil
            if old.done, old.resolvedKind == .warmup, fraction == nil, let kg = old.kg, let oldTarget, oldTarget > 0 {
                fraction = kg / oldTarget
            }
            var next = TrainingSet(number: offset + 1, kg: old.done ? old.kg : nil, reps: old.done ? old.reps : nil, kind: old.resolvedKind,
                               toFailure: old.toFailure, supersetGroup: old.supersetGroup, loadFraction: fraction)
            next.durationSeconds = old.done ? old.durationSeconds : nil
            next.leftSeconds = old.done ? old.leftSeconds : nil; next.rightSeconds = old.done ? old.rightSeconds : nil
            next.restSeconds = old.restSeconds
            return next
        }
        let currentWorkingCount = result.filter { $0.resolvedKind != .warmup }.count
        if currentWorkingCount < prescribedWorkingSets {
            for _ in currentWorkingCount..<prescribedWorkingSets {
                result.append(TrainingSet(number: result.count + 1, kind: .working))
            }
        }
        rescaleWarmups(in: &result, workingLoad: oldTarget)
        return renumbered(result)
    }
    static func rememberWarmupFractions(in sets: inout [TrainingSet]) {
        guard let target = workingLoad(sets), target > 0 else { return }
        for index in sets.indices where sets[index].resolvedKind == .warmup {
            if let kg = sets[index].kg, kg > 0 { sets[index].loadFraction = kg / target }
        }
    }
    static func rescaleWarmups(in sets: inout [TrainingSet], workingLoad: Double?) {
        guard let workingLoad, workingLoad > 0 else { return }
        for index in sets.indices where sets[index].resolvedKind == .warmup && !sets[index].done {
            guard let fraction = sets[index].loadFraction, fraction.isFinite, fraction > 0 else { continue }
            sets[index].kg = roundedPlateLoad(workingLoad * fraction)
        }
    }
    static func renumbered(_ sets: [TrainingSet]) -> [TrainingSet] {
        sets.enumerated().map { offset, value in var copy = value; copy.number = offset + 1; return copy }
    }
    private static func roundedPlateLoad(_ value: Double) -> Double {
        max(0, (value / 2.5).rounded() * 2.5)
    }
}

struct TrainingExerciseLog: Codable, Identifiable, Equatable {
    var id: String { exercise.id }
    var exercise: TrainingExercise
    var sets: [TrainingSet]
    var notes: String = ""
}

struct TrainingSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var planID: UUID
    var dayName: String
    var calendarEventID: String?
    var start: Date
    var end: Date?
    var exercises: [TrainingExerciseLog]
    var notes: String = ""
    var updatedAt = Date()
    var dayID: String? = nil
    var rest: TrainingRest? = nil
}

struct TrainingLibrary: Codable {
    var plans: [TrainingPlan] = []
    var activePlanID: UUID?
    var sessions: [TrainingSession] = []
    var tips: [String: String] = [:]
    var activePlan: TrainingPlan? { plans.first { $0.id == activePlanID } }
    func previous(exerciseID: String, before: Date, excluding sessionID: UUID? = nil) -> TrainingExerciseLog? {
        sessions.filter { $0.id != sessionID && $0.end != nil && $0.start <= before }
            .sorted { $0.start > $1.start }.compactMap { $0.exercises.first { $0.id == exerciseID && $0.sets.contains(where: \.done) } }.first
    }
    func makeSession(plan: TrainingPlan, day: TrainingDay, eventID: String?, now: Date = Date()) -> TrainingSession {
        let logs = day.exercises.map { exercise in
            let last = previous(exerciseID: exercise.id, before: now)
            let sets = TrainingSetTemplate.next(previous: last, prescribedWorkingSets: exercise.sets)
            var resolved = exercise
            resolved.isometric = exercise.isometric ?? last?.exercise.isometric
            resolved.separateSides = exercise.separateSides ?? last?.exercise.separateSides
            resolved.weightedHold = exercise.weightedHold ?? last?.exercise.weightedHold
            return TrainingExerciseLog(exercise: resolved, sets: sets)
        }
        return TrainingSession(planID: plan.id, dayName: day.name, calendarEventID: eventID, start: now, exercises: logs, dayID: day.id)
    }
    func validate() throws {
        guard plans.count <= 6, Set(plans.map(\.id)).count == plans.count,
              activePlanID == nil || plans.contains(where: { $0.id == activePlanID }),
              Set(sessions.map(\.id)).count == sessions.count else { throw TrainingError.invalidPlan }
        for plan in plans {
            try plan.payload.validate()
            for revision in plan.revisions ?? [] { try revision.payload.validate() }
        }
        for session in sessions {
            guard session.end.map({ $0 >= session.start }) ?? true,
                  Set(session.exercises.map(\.id)).count == session.exercises.count else { throw TrainingError.invalidPlan }
            for log in session.exercises {
                guard log.exercise.isValid, (1...60).contains(log.sets.count), Set(log.sets.map(\.number)).count == log.sets.count,
                      log.sets.allSatisfy({ set in (1...60).contains(set.number)
                          && (set.kg.map { $0.isFinite && (0...2000).contains($0) } ?? true)
                          && (set.reps.map { (0...1000).contains($0) } ?? true)
                          && (set.loadFraction.map { $0.isFinite && (0...1.5).contains($0) } ?? true)
                          && (set.supersetGroup.map { $0.count <= 20 } ?? true)
                          && ([set.durationSeconds, set.leftSeconds, set.rightSeconds].allSatisfy { $0.map { (0...86400).contains($0) } ?? true })
                          && (set.restSeconds.map { (0...3600).contains($0) } ?? true)
                          && (set.actualRestSeconds.map { $0 >= 0 } ?? true)
                          && (!set.done || set.canComplete(log.exercise) || (set.holdTotal == 0 && set.kg != nil && set.reps != nil)) }) else { throw TrainingError.invalidPlan }
            }
        }
    }
}

enum TrainingError: LocalizedError {
    case missingPayload, invalidPlan
    var errorDescription: String? {
        switch self {
        case .missingPayload: return "Questo PDF non contiene una scheda Pivot. Mandami prima la scheda del personal in chat: la prepariamo senza inventare esercizi o carichi."
        case .invalidPlan: return "La scheda contiene dati mancanti o non validi. Non è stata importata."
        }
    }
}

enum TrainingPDFFormat {
    static let begin = "PIVOT-WORKOUT-V1"
    static let end = "END-PIVOT-WORKOUT"
    static func parse(_ text: String) throws -> TrainingPlanPayload {
        guard text.utf8.count <= 2 * 1024 * 1024,
              let from = text.range(of: begin), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else { throw TrainingError.missingPayload }
        let base64 = text[from.upperBound..<to.lowerBound].filter { !$0.isWhitespace }
        guard base64.count <= 1_000_000, let bytes = Data(base64Encoded: String(base64)) else { throw TrainingError.invalidPlan }
        do {
            let payload = try JSONDecoder().decode(TrainingPlanPayload.self, from: bytes)
            try payload.validate()
            return payload
        } catch { throw TrainingError.invalidPlan }
    }
    static func encodedBlock(_ payload: TrainingPlanPayload) throws -> String {
        try payload.validate()
        return begin + "\n" + (try JSONEncoder().encode(payload)).base64EncodedString() + "\n" + end
    }
}

enum TrainingExport {
    static func text(_ session: TrainingSession, library: TrainingLibrary) -> String {
        var rows = ["PIVOT — \(session.dayName)", "Data: \(PivotDate.key(session.start))", "Inizio: \(PivotDate.time(session.start))", "Fine: \(session.end.map(PivotDate.time) ?? "in corso")"]
        for log in session.exercises {
            rows.append("\n\(log.exercise.name) · programma \(log.exercise.sets) × \(log.exercise.reps)")
            if let last = library.previous(exerciseID: log.id, before: session.start, excluding: session.id) {
                rows.append("Precedente: " + last.sets.filter(\.done).map { last.exercise.usesDuration ? TrainingReports.performance($0, exercise: last.exercise) : "\($0.kg ?? 0) kg × \($0.reps ?? 0)" }.joined(separator: "; "))
            }
            for set in log.sets {
                let group = set.resolvedKind == .superset && !(set.supersetGroup ?? "").isEmpty ? " \(set.supersetGroup!)" : ""
                let failure = set.reachesFailure ? " · cedimento" : ""
                rows.append("Serie \(set.number) · \(set.resolvedKind.label)\(group): \(TrainingReports.performance(set, exercise: log.exercise)) · \(set.done ? "fatta" : "non fatta")\(failure) · recupero \(set.restSeconds ?? log.exercise.restSeconds) s")
            }
            if !log.notes.isEmpty { rows.append("Note: \(log.notes)") }
            if let tip = library.tips[log.id], !tip.isEmpty { rows.append("Promemoria tecnici: \(tip)") }
        }
        if !session.notes.isEmpty { rows.append("\nNote allenamento: \(session.notes)") }
        return rows.joined(separator: "\n")
    }
}
