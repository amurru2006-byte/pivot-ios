import Foundation

/// In-memory only: fresh workout totals are always read from HealthKit. Only
/// the extra associated-heart-rate query is cached, with a bounded lifetime.
struct HealthWorkoutCacheEntry {
    var summary: HealthWorkoutSummary
    var heartRateReadAt: Date?
    var heartRateAttemptedAt: Date? = nil

    func needsHeartRate(for fresh: HealthWorkoutSummary, now: Date, force: Bool) -> Bool {
        guard !force, let readAt = heartRateReadAt else { return true }
        let age = now.timeIntervalSince(readAt)
        let lifetime: TimeInterval = summary.averageBPM == nil ? 300 : 900
        guard age >= 0 && age < lifetime else { return true }
        var old = summary, incoming = fresh
        old.averageBPM = nil; incoming.averageBPM = nil
        return old != incoming
    }

    func compatibleHeartRate(for fresh: HealthWorkoutSummary) -> Int? {
        guard summary.id == fresh.id, summary.start == fresh.start, summary.end == fresh.end,
              summary.durationSeconds == fresh.durationSeconds, summary.type == fresh.type else { return nil }
        return summary.averageBPM
    }
}
