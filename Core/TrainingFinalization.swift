import Foundation

/// Prepare before saving: invalid timings must not partially close the live
/// session. Re-exporting a finished workout preserves its real end time.
enum TrainingFinalization {
    enum FinalizationError: LocalizedError {
        case invalidTiming
        var errorDescription: String? { "La fine deve essere successiva all’inizio. Controlla gli orari prima di terminare." }
    }
    static func completed(_ session: TrainingSession, now: Date = Date()) throws -> TrainingSession {
        let end = session.end ?? now
        guard session.start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end >= session.start else { throw FinalizationError.invalidTiming }
        var result = session
        TrainingCompletion.finishRest(in: &result, now: end)
        result.end = end
        result.updatedAt = now
        return result
    }
}

enum TrainingReportFiles {
    /// UUID identity avoids collisions between two workouts on the same day;
    /// renaming a day or correcting the time never creates a second report.
    static func url(for sessionID: UUID, directory: URL) -> URL {
        directory.appendingPathComponent("Pivot-allenamento-\(sessionID.uuidString).pdf")
    }
}
