import Foundation

enum ClientRegistry {
    enum Failure: Error { case invalid, ambiguous, missing }

    static func named(_ name: String, clients: [Client]) -> [Client] {
        let key = EventCoalescer.normalized(name)
        guard !key.isEmpty else { return [] }
        return clients.filter { client in ([client.name] + (client.calendarAliases ?? [])).contains { EventCoalescer.normalized($0) == key } }
    }

    // Updating a tariff does not recalculate old lessons or receipts.
    @discardableResult static func save(name: String, rateCents: Int, cadence: PaymentCadence,
                                       aliases: [String] = [], editingID: UUID? = nil,
                                       activity: IncomeActivityKind? = nil, billing: IncomeBilling? = nil,
                                       defaults: ClientDefaults? = nil, data: inout AppData) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, rateCents >= 0, rateCents <= 100_000_000, defaults?.isValid ?? true else { throw Failure.invalid }
        let matches = named(name, clients: data.clients)
        guard !matches.contains(where: { $0.id != editingID }), editingID != nil else {
            if editingID != nil || matches.count > 1 { throw Failure.ambiguous }
            if let existing = matches.first {
                return try save(name: existing.name, rateCents: rateCents, cadence: cadence,
                                aliases: (existing.calendarAliases ?? []) + aliases, editingID: existing.id,
                                activity: activity, billing: billing, defaults: defaults, data: &data)
            }
            let client = Client(name: name, rateCents: rateCents, paymentCadence: cadence,
                                calendarAliases: cleanAliases(aliases, name: name), activity: activity, billing: billing, defaults: defaults)
            data.clients.append(client); return client.id
        }
        guard let index = data.clients.firstIndex(where: { $0.id == editingID }) else { throw Failure.missing }
        let formerName = data.clients[index].name
        data.clients[index].name = name
        data.clients[index].rateCents = rateCents
        data.clients[index].paymentCadence = cadence
        data.clients[index].calendarAliases = cleanAliases(aliases + [formerName], name: name)
        if let activity { data.clients[index].activity = activity }
        if let billing { data.clients[index].billing = billing }
        if let defaults { data.clients[index].defaults = defaults }
        return data.clients[index].id
    }

    static func cleanAliases(_ aliases: [String], name: String) -> [String]? {
        var seen: Set<String> = [EventCoalescer.normalized(name)]
        let result = aliases.compactMap { alias -> String? in
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = EventCoalescer.normalized(value)
            return !key.isEmpty && seen.insert(key).inserted ? value : nil
        }
        return result.isEmpty ? nil : result
    }

    // Requires a human confirmation of both IDs. Equal names are NOT proof that
    // two profiles are the same person; never run this as an automatic migration.
    static func merge(sourceID: UUID, into targetID: UUID, data: inout AppData) throws {
        guard sourceID != targetID,
              let source = data.clients.first(where: { $0.id == sourceID }),
              let targetIndex = data.clients.firstIndex(where: { $0.id == targetID }) else { throw Failure.missing }
        let target = data.clients[targetIndex]
        // Do not silently discard conflicting per-contact preferences on merge.
        let sourceDefaults = source.defaults == ClientDefaults() ? nil : source.defaults
        let targetDefaults = target.defaults == ClientDefaults() ? nil : target.defaults
        guard sourceDefaults == nil || targetDefaults == nil || sourceDefaults == targetDefaults else { throw Failure.ambiguous }
        // Merging identities must not silently discard an explicit activation
        // choice. Ask the user to align conflicting choices before merging.
        if let a = source.activityState, let b = target.activityState,
           a.manuallyInactive != b.manuallyInactive { throw Failure.ambiguous }
        var mergedActivity = target.activityState ?? source.activityState
        if let a = source.activityState, let b = target.activityState {
            mergedActivity?.firstObservedAt = min(a.firstObservedAt, b.firstObservedAt)
            mergedActivity?.activatedAt = [a.activatedAt, b.activatedAt].compactMap { $0 }.max()
            mergedActivity?.lastCalendarActivityAt = [a.lastCalendarActivityAt, b.lastCalendarActivityAt].compactMap { $0 }.max()
            mergedActivity?.inactive = a.inactive && b.inactive
        }
        data.clients[targetIndex].activityState = mergedActivity
        data.clients[targetIndex].defaults = targetDefaults ?? sourceDefaults
        data.clients[targetIndex].calendarAliases = cleanAliases(
            (target.calendarAliases ?? []) + [source.name] + (source.calendarAliases ?? []), name: target.name)
        let incomeIDs = Set(data.income.filter { $0.clientID == sourceID }.map(\.id))
        for index in data.income.indices where data.income[index].clientID == sourceID {
            data.income[index].clientID = targetID; data.income[index].clientName = target.name
        }
        for index in data.payments.indices where incomeIDs.contains(data.payments[index].incomeID) {
            data.payments[index].clientName = target.name
        }
        if var drafts = data.activityDrafts {
            for key in Array(drafts.keys) where drafts[key]?.clientID == sourceID {
                drafts[key]?.clientID = targetID; drafts[key]?.studentName = target.name
            }
            data.activityDrafts = drafts
        }
        data.clients.removeAll { $0.id == sourceID }
    }
}
