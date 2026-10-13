import Foundation

/// Declared programming context, never a load prescription or medical clearance.
/// Absence means unknown; older sessions must not inherit a later plan's phase.
enum TrainingPhase: String, Codable, CaseIterable, Identifiable {
    case loading, deload, returning
    var id: String { rawValue }
    var label: String {
        switch self {
        case .loading: return "Carico"
        case .deload: return "Scarico"
        case .returning: return "Recupero / rientro"
        }
    }
    static func resolved(plan: TrainingPlanPayload, day: TrainingDay) -> TrainingPhase? {
        day.phase ?? plan.phase
    }
}
