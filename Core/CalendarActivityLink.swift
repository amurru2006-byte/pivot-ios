import Foundation

/// A native creation receipt, never inferred from event names, URLs or proximity.
struct CalendarCreationReceipt: Equatable {
    var activity: CalendarItem
    var travel: CalendarItem?
    var isValid: Bool {
        guard CalendarEventBackup.valid(activity), !activity.isAllDay, activity.recurring != true else { return false }
        guard let travel else { return true }
        return CalendarEventBackup.valid(travel) && !travel.isAllDay && travel.recurring != true
            && travel.eventIdentifier != activity.eventIdentifier
            && travel.calendarIdentifier == activity.calendarIdentifier && travel.sourceIdentifier == activity.sourceIdentifier
            && CalendarSnapshotMatch.instant(travel.end, activity.start)
    }
}

/// Private durable state survives deleting the chat. The snapshots are optimistic
/// concurrency baselines, not authority to change a calendar without confirmation.
struct CalendarActivityLink: Codable, Identifiable, Equatable {
    var id: UUID // the locally prepared creation ID
    var activity: CalendarItem
    var travel: CalendarItem
    var settings: CalendarCreationTravel
    var capturedAt: Date
    var deleted: Bool = false
    var isValid: Bool {
        CalendarCreationReceipt(activity: activity, travel: travel).isValid && settings.isValid
            && !settings.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && capturedAt.timeIntervalSinceReferenceDate.isFinite
    }
}

enum CalendarActivityLinks {
    enum Failure: LocalizedError {
        case changed, route, selection, invalid
        var errorDescription: String? {
            switch self {
            case .changed: return "L’attività o il viaggio sono cambiati rispetto al collegamento salvato. Verifica entrambi nel Calendario: non li sovrascrivo."
            case .route: return "Verifica il viaggio per il nuovo orario: ricalcola con Maps oppure conferma un tempo manuale."
            case .selection: return "Attività e viaggio collegato vanno verificati insieme nell’anteprima modifiche della chat. Non applico solo una parte dello spostamento o dell’eliminazione."
            case .invalid: return "Non riesco a verificare il collegamento tra attività e viaggio. Nessuna modifica applicata."
            }
        }
    }
    static func valid(_ data: AppData) -> Bool {
        let links = data.calendarActivityLinks ?? []
        let identities = links.flatMap { [$0.activity, $0.travel] }.map { $0.calendarIdentifier + "|" + $0.eventIdentifier }
        return links.count <= 20_000 && links.allSatisfy(\.isValid)
            && Set(links.map(\.id)).count == links.count && Set(identities).count == identities.count
    }
    @discardableResult static func capture(id: UUID, receipt: CalendarCreationReceipt, options: CalendarCreationOptions,
        data: inout AppData, now: Date) -> Bool {
        guard receipt.isValid else { return false }
        guard let travel = receipt.travel else { return options.travel == nil }
        guard let settings = options.travel else { return false }
        let value = CalendarActivityLink(id: id, activity: receipt.activity, travel: travel, settings: settings, capturedAt: now)
        guard value.isValid else { return false }
        var next = data
        if let old = next.calendarActivityLinks?.first(where: { $0.id == id }) {
            // A retry is idempotent only for the exact same native revisions.
            return CalendarSnapshotMatch.revision(old.activity, value.activity)
                && CalendarSnapshotMatch.revision(old.travel, value.travel) && old.settings == settings
        }
        var links = next.calendarActivityLinks ?? []; links.append(value); next.calendarActivityLinks = links
        guard valid(next) else { return false }
        data.calendarActivityLinks = links; return true
    }
    static func link(for item: CalendarItem, data: AppData) -> CalendarActivityLink? {
        let matches = (data.calendarActivityLinks ?? []).filter { !$0.deleted && (
            CalendarSnapshotMatch.identity($0.activity, item) || CalendarSnapshotMatch.identity($0.travel, item)
        ) }
        return matches.count == 1 ? matches.first : nil
    }
    static func requiresPairedReview(_ item: CalendarItem, data: AppData) -> Bool {
        (data.calendarActivityLinks ?? []).contains { !$0.deleted && (
            CalendarSnapshotMatch.identity($0.activity, item) || CalendarSnapshotMatch.identity($0.travel, item)) }
    }
    static func archiving(_ entries: [ArchivedCalendarMutation], data: AppData) -> [ArchivedCalendarMutation] {
        entries.map { entry in
            var next = entry
            if let link = link(for: entry.original.snapshot, data: data),
               CalendarSnapshotMatch.identity(link.activity, entry.original.snapshot) { next.linkedTravelBefore = link.settings }
            return next
        }
    }
    /// Adopt a restore only after a full native pair from one archived batch is
    /// acknowledged. Half-restores stay on the old baseline and cannot pass the
    /// next preflight. Neither names nor calendar URLs establish a new link.
    static func reconcileRestorations(data: inout AppData) {
        let groups = Dictionary(grouping: data.calendarActionArchive ?? [], by: \.batchID)
        for index in (data.calendarActivityLinks ?? []).indices {
            guard let link = data.calendarActivityLinks?[index] else { continue }
            let candidates: [CalendarActivityLink] = groups.values.compactMap { entries in
                let main = entries.first { entry in
                    let baseline: CalendarItem? = link.deleted ? entry.original.snapshot : entry.after
                    return baseline.map { CalendarSnapshotMatch.revision(link.activity, $0) } ?? false
                }
                guard let main, main.status == .restored, let activity = main.restoredEvent,
                      let settings = main.linkedTravelBefore else { return nil }
                let trip = entries.first { entry in
                    let baseline: CalendarItem? = link.deleted ? entry.original.snapshot : entry.after
                    return baseline.map { CalendarSnapshotMatch.revision(link.travel, $0) } ?? false
                }
                var candidate = link
                if let trip {
                    guard trip.status == .restored, let travel = trip.restoredEvent else { return nil }
                    candidate.travel = travel
                } else {
                    guard !link.deleted, main.kind == .update,
                          CalendarSnapshotMatch.instant(activity.start, link.activity.start) else { return nil }
                }
                candidate.activity = activity; candidate.settings = settings; candidate.deleted = false
                return candidate.isValid ? candidate : nil
            }
            if candidates.count == 1 { data.calendarActivityLinks?[index] = candidates[0] }
        }
    }
    /// Expands only local, native-identity links. The cloud cannot add a journey
    /// by inventing a title/URL. Every generated action is still an uncommitted
    /// proposal, checked again against EventKit and displayed before confirmation.
    static func expanded(_ actions: [CoachCalendarMutation], data: AppData,
        choices: [String: CalendarCreationTravel], now: Date, mapsConsent: Bool) throws -> [CoachCalendarMutation] {
        guard valid(data) else { throw Failure.invalid }
        var result = actions
        for link in (data.calendarActivityLinks ?? []).filter({ !$0.deleted }) {
            let main = actions.first { CalendarSnapshotMatch.identity(link.activity, $0.source) }
            let trip = actions.first { CalendarSnapshotMatch.identity(link.travel, $0.source) }
            guard main != nil || trip != nil else { continue }
            guard let main else { throw Failure.selection }
            guard CalendarSnapshotMatch.revision(link.activity, main.source) else { throw Failure.changed }
            let desired: CoachCalendarMutation?
            if main.kind == .delete {
                desired = .init(kind: .delete, source: link.travel, after: nil)
            } else if let after = main.after, !CalendarSnapshotMatch.instant(after.start, link.activity.start) {
                // An old manual duration is a user estimate, not a live ETA.
                // Maps-based journeys require a new, explicit verified choice.
                guard let travel = choices[link.id.uuidString] ?? (link.settings.estimate == nil ? link.settings : nil) else { throw Failure.route }
                let draft = CoachCalendarDraft(title: after.title, start: after.start, end: after.end,
                    calendarHint: nil, notes: after.notes, endEstimated: false)
                var options = CalendarCreationOptions(); options.location = after.location; options.travel = travel
                guard options.problem(draft: draft, now: now, mapsConsent: mapsConsent) == nil,
                      let part = options.parts(draft: draft, creationID: link.id).first, part.isTravel else { throw Failure.route }
                var nextTrip = link.travel; nextTrip.start = part.start; nextTrip.end = part.end; nextTrip.notes = part.notes
                desired = .init(kind: .update, source: link.travel, after: nextTrip)
            } else { desired = nil }
            if let desired {
                guard desired.isValid else { throw Failure.invalid }
                if let trip {
                    guard trip.kind == desired.kind, CalendarSnapshotMatch.revision(trip.source, desired.source), trip.after == desired.after else { throw Failure.selection }
                } else { result.append(desired) }
            } else if trip != nil { throw Failure.selection }
        }
        guard result.count <= 10, Set(result.map { $0.source.id }).count == result.count else { throw Failure.invalid }
        return result
    }
    /// Called in the same local acknowledgement as the mutation archive. Never
    /// synthesize new links from arbitrary calendar updates or restore operations.
    static func record(_ completed: [ArchivedCalendarMutation], choices: [String: CalendarCreationTravel], data: inout AppData) throws {
        var next = data
        for index in (next.calendarActivityLinks ?? []).indices {
            guard var link = next.calendarActivityLinks?[index], !link.deleted else { continue }
            let main = completed.first { CalendarSnapshotMatch.identity(link.activity, $0.original.snapshot) }
            let trip = completed.first { CalendarSnapshotMatch.identity(link.travel, $0.original.snapshot) }
            guard main != nil || trip != nil else { continue }
            guard let main, main.status == .committed else { throw Failure.selection }
            if main.kind == .delete {
                guard trip?.kind == .delete, trip?.status == .committed else { throw Failure.selection }
                link.deleted = true
            } else {
                guard let after = main.after else { throw Failure.invalid }
                link.activity = after
                if let trip {
                    guard trip.status == .committed, let after = trip.after else { throw Failure.invalid }
                    link.travel = after
                    if let choice = choices[link.id.uuidString] { link.settings = choice }
                }
            }
            next.calendarActivityLinks?[index] = link
        }
        guard valid(next) else { throw Failure.invalid }
        data.calendarActivityLinks = next.calendarActivityLinks
    }
}
