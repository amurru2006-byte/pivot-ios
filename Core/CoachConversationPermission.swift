import Foundation

/// Ephemeral consent for today's conversation. Never stored in AppData/backups.
/// Provider configuration consent and calendar write approval remain separate.
struct CoachConversationPermission: Equatable {
    private var authorizedDay: String?

    mutating func authorize(dayKey: String) { authorizedDay = dayKey }
    mutating func revoke() { authorizedDay = nil }
    func allows(dayKey: String) -> Bool { authorizedDay == dayKey }
}
