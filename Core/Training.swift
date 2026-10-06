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
                guard !exercise.id.isEmpty, !exercise.name.isEmpty, !exercise.reps.isEmpty,
                      (1...30).contains(exercise.sets), (0...3600).contains(exercise.restSeconds) else { throw TrainingError.invalidPlan }
            }
        }
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

struct TrainingSet: Codable, Identifiable {
    var id = UUID()
    var number: Int
    var kg: Double?
    var reps: Int?
    var done = false
}

struct TrainingExerciseLog: Codable, Identifiable {
    var id: String { exercise.id }
    var exercise: TrainingExercise
    var sets: [TrainingSet]
    var notes: String = ""
}

struct TrainingSession: Codable, Identifiable {
    var id = UUID()
    var planID: UUID
    var dayName: String
    var calendarEventID: String?
    var start: Date
    var end: Date?
    var exercises: [TrainingExerciseLog]
    var notes: String = ""
    var updatedAt = Date()
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
            let sets = (1...exercise.sets).map { number -> TrainingSet in
                let old = last?.sets.first { $0.number == number && $0.done }
                return TrainingSet(number: number, kg: old?.kg, reps: old?.reps)
            }
            return TrainingExerciseLog(exercise: exercise, sets: sets)
        }
        return TrainingSession(planID: plan.id, dayName: day.name, calendarEventID: eventID, start: now, exercises: logs)
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
                guard Set(log.sets.map(\.number)).count == log.sets.count,
                      log.sets.allSatisfy({ set in (1...30).contains(set.number)
                          && (set.kg.map { $0.isFinite && (0...2000).contains($0) } ?? true)
                          && (set.reps.map { (0...1000).contains($0) } ?? true)
                          && (!set.done || (set.kg != nil && set.reps != nil)) }) else { throw TrainingError.invalidPlan }
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
                rows.append("Precedente: " + last.sets.filter(\.done).map { "\($0.kg ?? 0) kg × \($0.reps ?? 0)" }.joined(separator: "; "))
            }
            for set in log.sets { rows.append("Serie \(set.number): \(set.kg.map { String($0) } ?? "—") kg × \(set.reps.map(String.init) ?? "—") · \(set.done ? "fatta" : "non fatta")") }
            if !log.notes.isEmpty { rows.append("Note: \(log.notes)") }
            if let tip = library.tips[log.id], !tip.isEmpty { rows.append("Promemoria tecnici: \(tip)") }
        }
        if !session.notes.isEmpty { rows.append("\nNote allenamento: \(session.notes)") }
        return rows.joined(separator: "\n")
    }
}
