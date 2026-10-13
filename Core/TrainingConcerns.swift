import Foundation

enum TrainingConcernKind: String, Codable, CaseIterable, Identifiable {
    case pain, reportedInjury
    var id: String { rawValue }
    var label: String { self == .pain ? "Dolore / fastidio" : "Infortunio riferito" }
}

enum TrainingConcernSide: String, Codable, CaseIterable, Identifiable {
    case unspecified, left, right, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unspecified: return "Non specificato"
        case .left: return "Sinistro"
        case .right: return "Destro"
        case .both: return "Entrambi"
        }
    }
}

struct TrainingConcernExercise: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var catalogID: String?
    init(_ exercise: TrainingExercise) { id = exercise.id; name = exercise.name; catalogID = exercise.catalogID }
    func matches(_ exercise: TrainingExercise) -> Bool {
        // Cross-exercise links are explicit, not inferred from symptoms or anatomy.
        if let catalogID, let other = exercise.catalogID {
            return catalogID == other && EventCoalescer.normalized(name) == EventCoalescer.normalized(exercise.name)
        }
        return id == exercise.id && EventCoalescer.normalized(name) == EventCoalescer.normalized(exercise.name)
    }
}

struct TrainingConcern: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TrainingConcernKind = .pain
    var area = ""
    var side: TrainingConcernSide = .unspecified
    var intensity: Int? = nil
    var observedAt = Date()
    var notes = ""
    var professionalGuidance = ""
    var guidanceSource = ""
    var exercises: [TrainingConcernExercise] = []
    var originatingSessionID: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    var resolvedAt: Date? = nil
    var isActive: Bool { resolvedAt == nil }
    var location: String { side == .unspecified ? area : "\(area) · \(side.label)" }
    var isValid: Bool {
        !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && area.count <= 120
            && (intensity.map { (0...10).contains($0) } ?? true)
            && notes.count <= 4000 && professionalGuidance.count <= 4000 && guidanceSource.count <= 200
            && exercises.count <= 80 && Set(exercises.map(\.id)).count == exercises.count
            && exercises.allSatisfy { !$0.id.isEmpty && $0.id.count <= 500 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 500 && ($0.catalogID.map { !$0.isEmpty && $0.count <= 500 } ?? true) }
            && [observedAt, createdAt, updatedAt].allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite }
            && updatedAt >= createdAt && observedAt <= updatedAt
            && (resolvedAt.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 >= observedAt && $0 <= updatedAt } ?? true)
    }
}

enum TrainingConcerns {
    enum ConcernError: LocalizedError {
        case invalid, changed, unavailable
        var errorDescription: String? {
            switch self {
            case .invalid: return "Indica la zona e controlla lunghezza delle note, intensità e date. I dati precedenti sono conservati."
            case .changed: return "La segnalazione è cambiata altrove. Chiudi e riaprila prima di modificarla: non ho sovrascritto la nuova versione."
            case .unavailable: return "Attendi il caricamento o il ripristino prima di salvare."
            }
        }
    }
    static func active(for exercise: TrainingExercise, in library: TrainingLibrary) -> [TrainingConcern] {
        sorted((library.concerns ?? []).filter { $0.isActive && $0.exercises.contains { $0.matches(exercise) } })
    }
    static func sorted(_ values: [TrainingConcern]) -> [TrainingConcern] {
        values.sorted { $0.observedAt == $1.observedAt ? $0.id.uuidString < $1.id.uuidString : $0.observedAt > $1.observedAt }
    }
    static func saving(_ draft: TrainingConcern, expected: TrainingConcern?, in library: TrainingLibrary, now: Date = Date()) throws -> (library: TrainingLibrary, concern: TrainingConcern) {
        let existing = (library.concerns ?? []).first { $0.id == draft.id }
        guard existing == expected, expected == nil || expected?.id == draft.id else { throw ConcernError.changed }
        var saved = draft
        saved.area = saved.area.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.createdAt = existing?.createdAt ?? now
        if let existing { saved.originatingSessionID = existing.originatingSessionID }
        saved.updatedAt = max(now, saved.createdAt)
        guard saved.isValid else { throw ConcernError.invalid }
        var next = library
        var concerns = next.concerns ?? []
        if let index = concerns.firstIndex(where: { $0.id == saved.id }) { concerns[index] = saved }
        else { concerns.append(saved) }
        next.concerns = concerns
        try next.validate()
        return (next, saved)
    }
}
