import Foundation

enum StrengthBenchmark: String, Codable, CaseIterable, Identifiable {
    case bench, squat, deadlift
    var id: String { rawValue }
    var title: String {
        switch self { case .bench: return "Petto · panca piana"; case .squat: return "Gambe · squat"; case .deadlift: return "Catena posteriore · stacco" }
    }
    static func resolve(_ exercise: TrainingExercise) -> StrengthBenchmark? {
        guard !exercise.usesDuration, !TrainingRecords.isAssisted(exercise) else { return nil }
        if let catalog = exercise.catalogID {
            switch catalog {
            case "Barbell_Bench_Press_-_Medium_Grip": return .bench
            case "Barbell_Squat": return .squat
            case "Barbell_Deadlift": return .deadlift
            default: return nil
            }
        }
        if ExerciseCatalog.hasBenchIllustration(exercise) { return .bench }
        let key = EventCoalescer.normalized(exercise.name)
        if ["barbell squat", "squat con bilanciere", "back squat"].contains(key) { return .squat }
        if ["deadlift", "barbell deadlift", "stacco da terra con bilanciere", "stacco da terra"].contains(key) { return .deadlift }
        return nil
    }
}

struct StrengthRankResult: Equatable {
    var benchmark: StrengthBenchmark
    var level: Int
    var estimatedMax: Double
    var relativeStrength: Double
    var nextTargetKG: Double?
    var percentileFloor: Int?
}

enum StrengthRanking {
    static let sourceURL = "https://doi.org/10.1016/j.jsams.2024.07.005"
    // Seven motivational bands, anchored to published deciles. The names and
    // band grouping are Pivot's presentation, not scientific category names.
    static let percentileFloors = [0, 10, 30, 50, 70, 80, 90]
    static func result(benchmark: StrengthBenchmark, maximum: Double, profile: StrengthProfile, at date: Date = Date()) -> StrengthRankResult? {
        guard (try? profile.validate()) != nil, let age = profile.age(at: date), (12...96).contains(age),
              let mass = profile.bodyMassKG, let sex = profile.referenceSex,
              maximum.isFinite, maximum > 0 else { return nil }
        let group = age < 18 ? 0 : age <= 35 ? 1 : age <= 59 ? 2 : age <= 79 ? 3 : 4
        let deciles = StrengthNorms2024.deciles(sex: sex, benchmark: benchmark, ageGroup: group)
        let ratio = maximum / mass
        let thresholds = percentileFloors.dropFirst().map { deciles[$0 / 10 - 1] }
        let level = thresholds.filter { ratio + 1e-9 >= $0 }.count
        return .init(benchmark: benchmark, level: level, estimatedMax: maximum, relativeStrength: ratio,
                     nextTargetKG: level < thresholds.count ? thresholds[level] * mass : nil,
                     percentileFloor: level == 0 ? nil : percentileFloors[level])
    }
    static func bestMaximum(for benchmark: StrengthBenchmark, library: TrainingLibrary, current: TrainingSession? = nil, before: Date = Date()) -> Double? {
        var sessions = library.sessions.filter { $0.start <= before }
        if let current { sessions.removeAll { $0.id == current.id }; sessions.append(current) }
        return sessions.flatMap(\.exercises).filter { $0.skipped != true && StrengthBenchmark.resolve($0.exercise) == benchmark }
            .flatMap { log in log.sets.compactMap { TrainingRecords.maximum($0, exercise: log.exercise) } }.max()
    }
}

/// van den Hoek et al., JSAMS 27 (2024), 734–742, Tables 3 (female) and 4
/// (male), CC BY 4.0. Rows: ascending P10...P90; columns: age 12–17, 18–35,
/// 36–59, 60–79, 80+. Cut points only, not confidence limits. These are
/// age-stratified relative-strength norms for competitive powerlifters.
/// Height is collected in the profile but does not enter this published model.
/// Weight-class adjustment is not silently inferred from marginal tables.
enum StrengthNorms2024 {
    static func deciles(sex: StrengthReferenceSex, benchmark: StrengthBenchmark, ageGroup: Int) -> [Double] {
        let rows: [[Double]]
        switch (sex, benchmark) {
        case (.female, .squat): rows = [
            [1.01,1.23,1.01,0.72,0.29], [1.15,1.40,1.17,0.87,0.32], [1.26,1.52,1.30,0.99,0.49],
            [1.36,1.62,1.41,1.08,0.55], [1.45,1.72,1.51,1.17,0.67], [1.55,1.82,1.61,1.26,0.78],
            [1.65,1.93,1.73,1.36,0.90], [1.77,2.07,1.85,1.48,0.96], [1.95,2.26,2.05,1.65,1.01]]
        case (.female, .bench): rows = [
            [0.56,0.67,0.62,0.49,0.41], [0.63,0.77,0.70,0.56,0.43], [0.70,0.84,0.77,0.62,0.46],
            [0.75,0.90,0.84,0.67,0.49], [0.81,0.96,0.90,0.72,0.55], [0.87,1.03,0.97,0.77,0.59],
            [0.94,1.10,1.04,0.85,0.67], [1.02,1.20,1.14,0.93,0.74], [1.14,1.35,1.28,1.04,0.92]]
        case (.female, .deadlift): rows = [
            [1.26,1.49,1.32,1.11,0.61], [1.43,1.68,1.50,1.27,0.70], [1.55,1.82,1.64,1.39,0.84],
            [1.66,1.94,1.76,1.49,0.97], [1.76,2.06,1.88,1.60,1.16], [1.87,2.17,2.00,1.71,1.28],
            [1.98,2.30,2.13,1.85,1.47], [2.11,2.45,2.28,1.98,1.61], [2.30,2.66,2.51,2.19,1.68]]
        case (.male, .squat): rows = [
            [1.32,1.75,1.48,1.04,0.52], [1.52,1.93,1.67,1.23,0.79], [1.67,2.06,1.81,1.38,0.89],
            [1.80,2.17,1.92,1.50,0.99], [1.92,2.28,2.03,1.62,1.11], [2.04,2.38,2.13,1.74,1.22],
            [2.16,2.50,2.24,1.85,1.37], [2.30,2.63,2.38,1.98,1.52], [2.50,2.83,2.58,2.16,1.72]]
        case (.male, .bench): rows = [
            [0.85,1.19,1.13,0.88,0.61], [0.99,1.31,1.26,1.00,0.73], [1.09,1.40,1.36,1.09,0.80],
            [1.17,1.48,1.44,1.16,0.86], [1.24,1.56,1.51,1.23,0.93], [1.32,1.63,1.59,1.30,1.00],
            [1.40,1.71,1.67,1.38,1.10], [1.49,1.81,1.77,1.47,1.21], [1.63,1.96,1.92,1.60,1.31]]
        case (.male, .deadlift): rows = [
            [1.61,2.03,1.75,1.42,0.96], [1.85,2.24,1.95,1.61,1.12], [2.01,2.40,2.09,1.75,1.24],
            [2.15,2.51,2.22,1.89,1.40], [2.28,2.63,2.34,2.02,1.50], [2.41,2.75,2.46,2.14,1.63],
            [2.53,2.87,2.59,2.27,1.81], [2.69,3.03,2.75,2.44,2.07], [2.90,3.25,2.98,2.64,2.30]]
        }
        guard (0..<5).contains(ageGroup) else { return [] }
        return rows.map { $0[ageGroup] }
    }
}
