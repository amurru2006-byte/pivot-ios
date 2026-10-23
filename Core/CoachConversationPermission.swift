import Foundation

/// Ephemeral consent for today's conversation. Never stored in AppData/backups.
/// Provider configuration consent and calendar write approval remain separate.
struct CoachConversationPermission: Equatable {
    private var authorizedDay: String?
    private var authorizedPlanningSourceIDs: Set<String> = []

    mutating func authorize(dayKey: String) {
        if authorizedDay != dayKey { authorizedPlanningSourceIDs = [] }
        authorizedDay = dayKey
    }
    mutating func authorizePlanningSources(_ ids: [String], dayKey: String) {
        guard allows(dayKey: dayKey) else { return }
        authorizedPlanningSourceIDs.formUnion(ids)
    }
    mutating func revoke() { authorizedDay = nil; authorizedPlanningSourceIDs = [] }
    func allows(dayKey: String) -> Bool { authorizedDay == dayKey }
    func allowsPlanningSources(_ ids: [String], dayKey: String) -> Bool {
        allows(dayKey: dayKey) && Set(ids).isSubset(of: authorizedPlanningSourceIDs)
    }
}
