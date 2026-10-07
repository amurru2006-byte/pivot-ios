import Foundation

struct WorkoutGuideExercise: Codable, Identifiable, Equatable {
    var id: String
    var slug: String
    var name: String
    var equipment: String
    var primaryMuscle: String
    var secondaryMuscles: [String]

    func imageURL(frame: Int = 1) -> URL? {
        guard (1...3).contains(frame) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/bryllim/workout-guide/\(WorkoutGuideCatalog.sourceRevision)/packages/workout-guide/assets/\(slug)/frame-\(frame).png")
    }
}

enum WorkoutGuideCatalog {
    static let sourceRevision = "aac599224bb9780305239607ef98540b7e0ce389"

    static func load(from url: URL) throws -> [WorkoutGuideExercise] {
        let entries = try JSONDecoder().decode([WorkoutGuideExercise].self, from: Data(contentsOf: url))
        guard entries.count == 302, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ !$0.id.isEmpty && !$0.slug.isEmpty && !$0.name.isEmpty }) else {
            throw TrainingError.invalidPlan
        }
        return entries
    }

    static func match(_ exercise: TrainingExercise, catalogEntry: CatalogExercise?, in entries: [WorkoutGuideExercise]) -> WorkoutGuideExercise? {
        if let id = catalogEntry?.id, let slug = catalogAliases[id], let value = entries.first(where: { $0.slug == slug }) { return value }
        let names = [exercise.name, catalogEntry?.name, catalogEntry?.displayName].compactMap { $0 }.map(EventCoalescer.normalized)
        for name in names {
            if let slug = nameAliases[name], let value = entries.first(where: { $0.slug == slug }) { return value }
            let exact = entries.filter { EventCoalescer.normalized($0.name) == name || EventCoalescer.normalized($0.slug) == name }
            if exact.count == 1 { return exact[0] }
        }
        return nil
    }

    // Conservative aliases only: ambiguous labels (for example "Lunges" or
    // generic calf raises) still ask the user to choose the exact variant.
    static let nameAliases: [String: String] = [
        "bench press": "bench-press",
        "dumbbell incline press": "incline-dumbbell-press",
        "machine low row": "machine-row",
        "machine rear delt": "reverse-pec-deck",
        "dumbbell lateral raise": "lateral-raise",
        "military press": "overhead-press",
        "hammer curls": "hammer-curl",
        "tricep pushdown": "tricep-pushdown",
        "barbell squat": "squat",
        "leg extensions": "leg-extension"
    ]

    static let catalogAliases: [String: String] = [
        "Barbell_Bench_Press_-_Medium_Grip": "bench-press",
        "Incline_Dumbbell_Press": "incline-dumbbell-press",
        "Face_Pull": "face-pull",
        "Hammer_Curls": "hammer-curl",
        "Triceps_Pushdown": "tricep-pushdown",
        "Barbell_Deadlift": "deadlift",
        "Barbell_Squat": "squat",
        "Romanian_Deadlift": "romanian-deadlift",
        "Leg_Extensions": "leg-extension",
        "Seated_Leg_Curl": "seated-leg-curl",
        "Plank": "plank",
        "Cable_Crossover": "cable-fly",
        "Side_Lateral_Raise": "lateral-raise",
        "Standing_Military_Press": "overhead-press"
    ]
}
