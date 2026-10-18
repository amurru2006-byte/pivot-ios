import Foundation

struct RecoveryPlanningPreferences: Codable, Equatable {
    var horizonDays: Int = 7
    var preferredBand: TrainingDurationTimeBand? = nil
    var confirmedAt = Date()
    var expiresAt: Date? = nil
    var isValid: Bool {
        (1...7).contains(horizonDays) && confirmedAt.timeIntervalSinceReferenceDate.isFinite
            && (expiresAt.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 > confirmedAt } ?? true)
    }
    func isActive(at now: Date) -> Bool {
        isValid && now.timeIntervalSinceReferenceDate.isFinite && confirmedAt <= now && (expiresAt.map { $0 > now } ?? true)
    }
}
