import Foundation

/// Transient execution state, separate from the last successfully read report.
/// Contains no samples, identifiers or underlying error descriptions and is not backed up.
struct HealthRefreshAttempt: Equatable {
    enum Outcome: Equatable {
        case inProgress, succeeded, partial, failed, cancelled, deferred
    }

    enum Stage: Equatable {
        case availability, authorization, sleep, workouts, heartRate, reconciliation, persistence
    }

    enum Cause: Equatable {
        case unavailable, authorizationFailed, queryFailed, persistenceFailed, changed, deferredDetails
    }

    let startedAt: Date
    let finishedAt: Date?
    let outcome: Outcome
    let failureStage: Stage?
    let failureCause: Cause?

    init?(startedAt: Date) {
        guard Self.validDate(startedAt) else { return nil }
        self.init(startedAt: startedAt, finishedAt: nil, outcome: .inProgress,
                  failureStage: nil, failureCause: nil)
    }

    private init(startedAt: Date, finishedAt: Date?, outcome: Outcome,
                 failureStage: Stage?, failureCause: Cause?) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.failureStage = failureStage
        self.failureCause = failureCause
    }

    /// A terminal outcome cannot be overwritten by a later callback.
    /// Reading no samples is still a successful read; it proves no permission state.
    func finishing(_ outcome: Outcome, at date: Date,
                   stage: Stage? = nil, cause: Cause? = nil) -> Self? {
        guard self.outcome == .inProgress, outcome != .inProgress,
              Self.validDate(date), date >= startedAt else { return nil }
        if outcome == .succeeded || outcome == .cancelled {
            guard stage == nil, cause == nil else { return nil }
        }
        return .init(startedAt: startedAt, finishedAt: date, outcome: outcome,
                     failureStage: stage, failureCause: cause)
    }

    /// Fixed local copy prevents private HealthKit or storage errors reaching the UI.
    var message: String {
        switch outcome {
        case .inProgress:
            return "Aggiornamento Salute in corso…"
        case .succeeded:
            return "Lettura completata."
        case .partial:
            return failureStage == .heartRate
                ? "Lettura parziale: dettagli cardiaci non aggiornati."
                : "Lettura completata solo in parte."
        case .failed:
            if failureStage == .availability { return "Salute non è disponibile." }
            if failureStage == .authorization || failureCause == .authorizationFailed {
                return "Non è stato possibile completare l’accesso a Salute."
            }
            if failureStage == .persistence { return "Aggiornamento locale non salvato." }
            return "Lettura da Salute non completata."
        case .cancelled:
            return "Aggiornamento interrotto."
        case .deferred:
            return failureCause == .changed
                ? "Aggiornamento rimandato: il contesto è cambiato."
                : "Aggiornamento rimandato."
        }
    }

    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}

/// Keeps the current attempt and the last applied reading consistent in memory.
/// A failed, cancelled or deferred attempt never changes the previous report.
struct HealthRefreshState: Equatable {
    private(set) var lastAttempt: HealthRefreshAttempt?
    private(set) var lastReport: HealthRefreshReport?

    init() {}

    @discardableResult
    mutating func begin(at date: Date) -> Bool {
        guard lastAttempt?.outcome != .inProgress,
              let attempt = HealthRefreshAttempt(startedAt: date) else { return false }
        lastAttempt = attempt
        return true
    }

    /// Updates both values atomically, after validating the complete transition.
    /// Only an applied successful or partial reading can replace the report.
    @discardableResult
    mutating func finish(_ outcome: HealthRefreshAttempt.Outcome, at date: Date,
                         stage: HealthRefreshAttempt.Stage? = nil,
                         cause: HealthRefreshAttempt.Cause? = nil,
                         report: HealthRefreshReport? = nil) -> Bool {
        guard let attempt = lastAttempt,
              let finished = attempt.finishing(outcome, at: date, stage: stage, cause: cause) else { return false }
        switch outcome {
        case .succeeded, .partial:
            guard let report, report.readAt.timeIntervalSinceReferenceDate.isFinite,
                  report.readAt >= attempt.startedAt, report.readAt <= date else { return false }
        case .failed, .cancelled, .deferred:
            guard report == nil else { return false }
        case .inProgress:
            return false
        }
        lastAttempt = finished
        if let report { lastReport = report }
        return true
    }
}
