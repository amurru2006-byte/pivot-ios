import Foundation

struct CatalogExercise: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var equipment: String?
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var category: String
    var images: [String]
    var displayName: String { ExerciseCatalog.italianNames[id] ?? name }
    var equipmentLabel: String { ExerciseCatalog.equipmentNames[equipment ?? ""] ?? equipment ?? "Non indicato" }
    var muscleSummary: String { primaryMuscles.map { ExerciseCatalog.muscleNames[$0] ?? $0 }.joined(separator: ", ") }
    var secondarySummary: String { secondaryMuscles.map { ExerciseCatalog.muscleNames[$0] ?? $0 }.joined(separator: ", ") }
    var photoURL: URL? {
        guard let path = images.first else { return nil }
        return URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/\(ExerciseCatalog.sourceRevision)/exercises/\(path)")
    }
    func prescription() -> TrainingExercise {
        // User/coach supplies series and reps; these are explicitly editable placeholders.
        TrainingExercise(id: "catalog:\(id)", name: displayName, sets: 1, reps: "Da concordare", restSeconds: 0, coachNotes: "", catalogID: id)
    }
}

enum ExerciseCatalog {
    static let sourceRevision = "f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5"
    static func load(from url: URL) throws -> [CatalogExercise] {
        let entries = try JSONDecoder().decode([CatalogExercise].self, from: Data(contentsOf: url))
        guard !entries.isEmpty, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.images.allSatisfy { !$0.contains("..") && !$0.hasPrefix("/") } }) else { throw TrainingError.invalidPlan }
        return entries
    }
    static func match(_ exercise: TrainingExercise, in entries: [CatalogExercise]) -> CatalogExercise? {
        if let id = exercise.catalogID { return entries.first { $0.id == id } }
        let name = EventCoalescer.normalized(exercise.name)
        let matches = entries.filter { EventCoalescer.normalized($0.name) == name || EventCoalescer.normalized($0.displayName) == name }
        return matches.count == 1 ? matches[0] : nil
    }
    static func hasBenchIllustration(_ exercise: TrainingExercise) -> Bool {
        if let id = exercise.catalogID { return id == "Barbell_Bench_Press_-_Medium_Grip" }
        return ["panca piana", "panca piana bilanciere", "panca piana con bilanciere", "barbell bench press medium grip", "flat barbell bench press"].contains(EventCoalescer.normalized(exercise.name))
    }
    static let italianNames: [String: String] = [
        "Barbell_Bench_Press_-_Medium_Grip": "Panca piana con bilanciere",
        "Barbell_Incline_Bench_Press_-_Medium_Grip": "Panca inclinata con bilanciere",
        "Dumbbell_Bench_Press": "Panca piana con manubri", "Incline_Dumbbell_Press": "Panca inclinata con manubri",
        "Barbell_Full_Squat": "Squat completo con bilanciere", "Barbell_Squat": "Squat con bilanciere",
        "Front_Barbell_Squat": "Front squat", "Barbell_Deadlift": "Stacco da terra con bilanciere",
        "Romanian_Deadlift": "Stacco rumeno", "Leg_Press": "Leg press", "Leg_Extensions": "Leg extension",
        "Lying_Leg_Curls": "Leg curl sdraiato", "Seated_Leg_Curl": "Leg curl seduto",
        "Bent_Over_Barbell_Row": "Rematore con bilanciere", "One-Arm_Dumbbell_Row": "Rematore con manubrio",
        "Wide-Grip_Lat_Pulldown": "Lat machine presa larga", "Pullups": "Trazioni", "Chin-Up": "Trazioni presa supina",
        "Seated_Cable_Rows": "Rematore al cavo", "Dumbbell_Shoulder_Press": "Spinte spalle con manubri",
        "Standing_Military_Press": "Military press", "Side_Lateral_Raise": "Alzate laterali",
        "Barbell_Curl": "Curl con bilanciere", "Dumbbell_Bicep_Curl": "Curl con manubri",
        "Hammer_Curls": "Curl a martello", "Triceps_Pushdown": "Pushdown tricipiti", "Dips_-_Triceps_Version": "Dip per tricipiti",
        "Standing_Calf_Raises": "Calf in piedi", "Seated_Calf_Raise": "Calf seduto", "Crunches": "Crunch", "Plank": "Plank"
    ]
    static let muscleNames = ["chest": "Pettorali", "shoulders": "Spalle", "triceps": "Tricipiti", "biceps": "Bicipiti", "forearms": "Avambracci", "abdominals": "Addominali", "quadriceps": "Quadricipiti", "hamstrings": "Ischiocrurali", "glutes": "Glutei", "calves": "Polpacci", "lats": "Dorsali", "middle back": "Dorso centrale", "lower back": "Zona lombare", "traps": "Trapezio", "adductors": "Adduttori", "abductors": "Abduttori", "neck": "Collo"]
    static let equipmentNames = ["barbell": "Bilanciere", "dumbbell": "Manubri", "cable": "Cavi", "machine": "Macchina", "body only": "Corpo libero", "kettlebells": "Kettlebell", "bands": "Elastici", "medicine ball": "Palla medica", "exercise ball": "Fitball", "e-z curl bar": "Bilanciere EZ", "foam roll": "Foam roller", "other": "Altro"]
}
