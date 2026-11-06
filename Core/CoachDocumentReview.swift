import Foundation

/// Bounded local reading/review, not permission to send its text to a provider.
/// PDFs remain single library files; citations and pages survive app relaunch.
struct CoachDocumentReviewBatch: Codable, Identifiable, Equatable {
    var id: UUID { packet.id }
    var packet: CoachDocumentPacket
    var events: [CoachDocumentEventProposal]
    var questions: [String]
    var stagedProposalIDs: [UUID] = []
    var updatedAt: Date
    var parentReviewID: UUID? = nil
    var exchange: CoachDocumentExchange.Scope? = nil

    func isValid(sources: [CoachDocumentSource]) -> Bool {
        guard packet.isValid, CoachPlanningSession.validDate(updatedAt), updatedAt >= packet.createdAt,
              events.count <= 20, Set(events.map(\.id)).count == events.count,
              Self.validQuestions(questions), Set(stagedProposalIDs).count == stagedProposalIDs.count,
              stagedProposalIDs.allSatisfy({ id in events.contains { $0.id == id } }),
              parentReviewID != id, exchange?.isValid(for: self) ?? true else { return false }
        // A restore allocates new physical IDs. Retained readings remain valid
        // history, but packet.isCurrent still blocks staging until reread.
        guard packet.sources.allSatisfy({ old in
            guard let current = sources.first(where: { $0.id == old.id }) else { return false }
            var logical = old; logical.document.id = current.document.id
            return logical == current
        }) else { return false }
        return events.allSatisfy { event in
            !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && event.title.count <= 160
                && event.notes.count <= 1800 && Self.validQuestions(event.questions)
                && [event.day, event.startClock, event.endDay, event.endClock].allSatisfy({ ($0?.utf16.count ?? 0) <= 10 })
                && (1...6).contains(event.citations.count) && event.citations.allSatisfy({ $0.isGrounded(in: packet) })
        }
    }
    private static func validQuestions(_ values: [String]) -> Bool {
        values.count <= 16 && values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 240 }
    }
}

enum CoachDocumentReviewStore {
    enum Failure: LocalizedError {
        case invalid, stale, limit, clarification, alreadyPrepared, notes
        var errorDescription: String? {
            switch self {
            case .invalid: return "La lettura o le proposte non sono verificabili. Nessuna bozza è stata aggiunta."
            case .stale: return "L’archivio o le fonti sono cambiati. Rileggi le pagine prima di preparare nuove bozze."
            case .limit: return "Le letture salvate hanno raggiunto il limite locale. Le precedenti restano intatte."
            case .clarification: return "Chiarisci data, anno e orari delle proposte selezionate. Non ho inventato le parti mancanti."
            case .alreadyPrepared: return "Una proposta selezionata ha già una bozza. Apri quella salvata: non ne ho creata una seconda."
            case .notes: return "Note e riferimenti superano lo spazio dell’evento. Riduci le note o le pagine citate, senza perdere gli originali."
            }
        }
    }
    static func valid(_ data: AppData) -> Bool {
        let batches = data.coachDocumentReviews ?? []
        return batches.count <= 20 && Set(batches.map(\.id)).count == batches.count
            && batches.reduce(0, { $0 + $1.packet.pages.reduce(0, { $0 + $1.text.utf16.count }) }) <= 500_000
            && batches.allSatisfy { $0.isValid(sources: data.coachDocuments ?? []) }
    }
    /// Retained staging records are tombstones even if a conversation/draft was
    /// removed later. Rereading an identical appointment cannot recreate it.
    static func preparedDraftID(for event: CoachDocumentEventProposal, in data: AppData) -> UUID? {
        for batch in data.coachDocumentReviews ?? [] {
            for old in batch.events where batch.stagedProposalIDs.contains(old.id) {
                if sameAppointment(old, event) { return old.id }
            }
        }
        return nil
    }
    private static func sameAppointment(_ first: CoachDocumentEventProposal, _ last: CoachDocumentEventProposal) -> Bool {
        first.kind == last.kind && first.timing == last.timing
            && first.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == last.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A second identical reading reopens its review, preserving user edits and
    /// staged IDs. It never duplicates a PDF or overwrites an earlier review.
    @discardableResult static func save(packet: CoachDocumentPacket, review: CoachDocumentEventResponse.Review,
                                       data: inout AppData, now: Date = Date()) throws -> UUID {
        guard valid(data), packet.isCurrent(in: data.coachDocuments ?? []),
              CoachPlanningSession.validDate(now), now >= packet.createdAt else { throw Failure.stale }
        let old = data.coachDocumentReviews ?? []
        if let existing = old.first(where: {
            $0.packet.instruction == packet.instruction && $0.packet.sources == packet.sources && $0.packet.pages == packet.pages
        }) { return existing.id }
        guard old.count < 20, !old.contains(where: { $0.id == packet.id }) else { throw Failure.limit }
        let batch = CoachDocumentReviewBatch(packet: packet, events: review.events, questions: review.questions, updatedAt: now)
        var next = data; next.coachDocumentReviews = old + [batch]
        guard valid(next) else { throw Failure.invalid }
        data = next; return batch.id
    }

    /// Explicit corrections remain local, grounded in the retained source. A
    /// staged proposal is immutable here; the existing draft editor owns edits.
    static func update(batchID: UUID, expected: CoachDocumentReviewBatch, event: CoachDocumentEventProposal,
                       data: inout AppData, now: Date = Date()) throws {
        guard valid(data), let index = data.coachDocumentReviews?.firstIndex(where: { $0.id == batchID }),
              data.coachDocumentReviews?[index] == expected, CoachPlanningSession.validDate(now), now >= expected.updatedAt,
              expected.packet.isCurrent(in: data.coachDocuments ?? []) else { throw Failure.stale }
        guard !expected.stagedProposalIDs.contains(event.id),
              let row = expected.events.firstIndex(where: { $0.id == event.id }) else { throw Failure.alreadyPrepared }
        var next = data
        next.coachDocumentReviews?[index].events[row] = event
        next.coachDocumentReviews?[index].exchange = nil
        next.coachDocumentReviews?[index].updatedAt = now
        guard valid(next) else { throw Failure.invalid }
        data = next
    }

    /// Metadata staging only. No Calendar lookup/write, selected native account,
    /// provider call, travel inference or external confirmation is performed.
    @discardableResult static func stage(batchID: UUID, expected: CoachDocumentReviewBatch, selected: [UUID],
                                        data: inout AppData, now: Date = Date(), nativeTimeZone: TimeZone = .current) throws -> [UUID] {
        guard valid(data), CoachDraftStore.valid(data.coachState),
              let index = data.coachDocumentReviews?.firstIndex(where: { $0.id == batchID }),
              data.coachDocumentReviews?[index] == expected,
              expected.packet.isCurrent(in: data.coachDocuments ?? []),
              CoachPlanningSession.validDate(now), now >= expected.updatedAt,
              (1...20).contains(selected.count), Set(selected).count == selected.count,
              selected.allSatisfy({ id in expected.events.contains { $0.id == id } }) else { throw Failure.stale }
        guard selected.allSatisfy({ !expected.stagedProposalIDs.contains($0) }),
              !(data.coachState.calendarDrafts ?? []).contains(where: { selected.contains($0.id) }) else { throw Failure.alreadyPrepared }
        let chosen = selected.compactMap { id in expected.events.first { $0.id == id } }
        for (position, event) in chosen.enumerated() {
            guard !chosen.prefix(position).contains(where: { sameAppointment($0, event) }) else { throw Failure.alreadyPrepared }
        }
        var next = data, coach = data.coachState
        for id in selected {
            guard let event = expected.events.first(where: { $0.id == id }) else { throw Failure.invalid }
            guard preparedDraftID(for: event, in: data) == nil else { throw Failure.alreadyPrepared }
            let start: Date, end: Date
            var options = CalendarCreationOptions()
            switch event.timing {
            case .allDay(let day):
                let allDay = CalendarCreationAllDay(day: day, nativeTimeZoneIdentifier: nativeTimeZone.identifier)
                guard allDay.isValid, let interval = allDay.canonicalInterval else { throw Failure.clarification }
                start = interval.start; end = interval.end; options.allDay = allDay
            case .timed(let first, let last): start = first; end = last
            case .needsClarification: throw Failure.clarification
            }
            var lines = [String]()
            for ref in event.references {
                guard let source = expected.packet.sources.first(where: { $0.id == ref.sourceID }), let first = ref.pages.first,
                      let url = CoachDocumentLibrary.url(sourceID: source.id, page: first, sources: expected.packet.sources) else { throw Failure.invalid }
                lines.append(source.document.name + " · pagine " + ref.pages.map(String.init).joined(separator: ", ") + "\n" + url.absoluteString)
            }
            let notes = (event.notes.isEmpty ? "" : event.notes + "\n\n") + "Fonti conservate in Pivot:\n" + lines.joined(separator: "\n")
            guard notes.count <= 3000 else { throw Failure.notes }
            let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach,
                text: "Proposta da documenti: \(event.title). Controlla citazioni, date e orari prima di confermare il Calendario.",
                createdAt: now, onlineHistoryEligible: false)
            let draft = CoachCalendarDraft(title: event.title, start: start, end: end, calendarHint: nil, notes: notes, endEstimated: false)
            let saved = CoachSavedCalendarDraft(id: id, messageID: message.id, dayKey: message.dayKey, draft: draft,
                createdAt: now, updatedAt: now, creationOptions: options, documentReferences: event.references)
            coach.messages.append(message)
            coach.calendarDrafts = (coach.calendarDrafts ?? []) + [saved]
        }
        next.coachState = coach
        next.coachDocumentReviews?[index].stagedProposalIDs += selected
        next.coachDocumentReviews?[index].exchange = nil
        next.coachDocumentReviews?[index].updatedAt = now
        guard valid(next), CoachDraftStore.valid(coach), CoachDocumentLibrary.valid(next) else { throw Failure.invalid }
        data = next
        return selected
    }
}
