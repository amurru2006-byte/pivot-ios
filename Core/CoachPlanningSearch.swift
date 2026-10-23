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
        let source = current.sources[0]
        let rule = EventRule.effective(for: source, data: data)
        // Invalid or stale logistics are a review, not proof of a full agenda.
        // Validate bounded components before reading occupiedMinutes: callers
        // can construct this value directly with overflowing integer fields.
        guard budget == CalendarTimeBudget.confirmed(activityMinutes: budget.activityMinutes, rule: rule,
            preparationMinutes: budget.preparationMinutes, marginMinutes: budget.marginMinutes) else {
            throw Failure.reviewRequired
        }
        guard !current.allowedIntervals.isEmpty else { return [] }
        // The allowed interval contains the entire occupied envelope: getting
        // ready, the journey, the activity and the confirmed return/margin.
        return CalendarRecoveryWindows.find(target: source, budget: budget, events: events, data: data,
            otherBudgets: otherBudgets, now: now, days: 7, within: current.allowedIntervals)
    }
}
