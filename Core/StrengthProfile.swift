import Foundation

enum StrengthReferenceSex: String, Codable, CaseIterable, Identifiable {
    case female, male
    var id: String { rawValue }
    var label: String { self == .female ? "Femminile" : "Maschile" }
}

struct StrengthProfile: Codable, Equatable {
    var birthDate: Date? = nil
    var bodyMassKG: Double? = nil
    var heightCM: Double? = nil
    var referenceSex: StrengthReferenceSex? = nil
    var measuredAt: Date? = nil
    func age(at date: Date = Date()) -> Int? {
        birthDate.flatMap { PivotDate.calendar.dateComponents([.year], from: $0, to: date).year }
    }
    func validate() throws {
        guard birthDate.map({ $0 <= Date() && (0...120).contains(age() ?? -1) }) ?? true,
              bodyMassKG.map({ $0.isFinite && (20...350).contains($0) }) ?? true,
              heightCM.map({ $0.isFinite && (80...250).contains($0) }) ?? true else { throw TrainingError.invalidPlan }
    }
}
