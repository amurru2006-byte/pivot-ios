import Foundation

/// Future C3 local search adapter, not connected to the online DTO or UI.
/// Returns alternatives for ONE activity, never native writes or AI-authored
/// times. Multiple activities need a joint solver, not independent proposals
/// that could overlap each other. No guessed pauses or medical rules.
enum CoachPlanningSearch {
    enum Failure: Error, Equatable { case reviewRequired, jointPlanningRequired }

    static func alternatives(for selection: CoachPlanningSelection, budget: CalendarTimeBudget,
                             access: CoachPlanningSelection.Access, events: [CalendarItem], data: AppData,
                             otherBudgets: [String: CalendarTimeBudget] = [:], now: Date) throws -> [CalendarRecoveryWindow] {
        let current = try selection.revalidated(access: access, events: events, data: data, now: now)
        guard current.sources.count == 1 else { throw Failure.jointPlanningRequired }
        guard current.unconfirmedTravelIDs.isEmpty, current.pairedReviewIDs.isEmpty else { throw Failure.reviewRequired }
        guard !current.allowedIntervals.isEmpty else { return [] }
        // The allowed interval contains the entire occupied envelope: getting
        // ready, the journey, the activity and the confirmed return/margin.
        return CalendarRecoveryWindows.find(target: current.sources[0], budget: budget, events: events, data: data,
            otherBudgets: otherBudgets, now: now, days: 7, within: current.allowedIntervals)
    }
}
