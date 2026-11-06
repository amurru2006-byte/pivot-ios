import Foundation

/// Shared logical references keep one immutable PDF for many drafts/events.
/// Native Calendar IDs stay local and never enter a document provider request.
struct CoachDocumentReference: Codable, Equatable {
    var sourceID: UUID
    var pages: [Int]
    func isValid(in sources: [CoachDocumentSource]) -> Bool {
        guard let source = sources.first(where: { $0.id == sourceID }), source.isValid,
              (1...40).contains(pages.count), Set(pages).count == pages.count else { return false }
        return pages.allSatisfy { (1...source.pageCount).contains($0) }
    }
}

struct CoachDocumentEventLink: Codable, Equatable {
    var eventID: String
    var references: [CoachDocumentReference]
}

enum CoachDocumentLibrary {
    enum ImportFailure: LocalizedError {
        case inconsistent, changed, duplicate, limit
        var errorDescription: String? {
            switch self {
            case .inconsistent: return "Non riesco a verificare l’archivio dei documenti. Nessuna fonte è stata sostituita."
            case .changed: return "La fonte o l’archivio sono cambiati. Rileggi il documento prima di riprovare."
            case .duplicate: return "Questa fonte è già presente. Selezionala nella libreria invece di creare una seconda copia."
            case .limit: return "Hai raggiunto il limite della libreria dei documenti. Non ho aggiunto altre copie."
            }
        }
    }
    /// Metadata only; the caller must validate, write and synchronize the new
    /// immutable PDF before calling this. Recheck against current AppData after
    /// every await. An old physical file is never overwritten or deleted.
    static func register(_ source: CoachDocumentSource, replacing expected: CoachDocumentSource? = nil,
                         data: inout AppData) throws {
        guard valid(data), data.studyPDFs == nil, source.isValid else { throw ImportFailure.inconsistent }
        var sources = data.coachDocuments ?? []
        guard !StudyFiles.documents(in: data).contains(where: { $0.id == source.document.id }) else { throw ImportFailure.changed }
        if let expected {
            guard let index = sources.firstIndex(where: { $0.id == expected.id }), sources[index] == expected,
                  source.id == expected.id, source.document.id != expected.document.id else { throw ImportFailure.changed }
            var permitted = expected; permitted.document.id = source.document.id
            guard source == permitted else { throw ImportFailure.changed }
            sources[index] = source
        } else {
            guard sources.count < 128 else { throw ImportFailure.limit }
            guard !sources.contains(where: { $0.id == source.id }) else { throw ImportFailure.changed }
            guard !sources.contains(where: { $0.sha256 == source.sha256 }) else { throw ImportFailure.duplicate }
            sources.append(source)
        }
        var next = data; next.coachDocuments = sources
        // Uses the existing combined budget for study, training and chat PDFs.
        // A failure leaves the input AppData exactly as it was.
        try StudyFiles.validateBackup(next)
        guard valid(next) else { throw ImportFailure.inconsistent }
        data = next
    }
    static func validReferences(_ refs: [CoachDocumentReference], sources: [CoachDocumentSource]) -> Bool {
        refs.count <= 6 && Set(refs.map(\.sourceID)).count == refs.count
            && refs.allSatisfy { $0.isValid(in: sources) }
    }
    static func valid(_ data: AppData) -> Bool {
        let sources = data.coachDocuments ?? [], links = data.coachDocumentEventLinks ?? []
        guard CoachDocumentSource.validLibrary(sources), links.count <= 10_000,
              Set(links.map(\.eventID)).count == links.count,
              links.allSatisfy({ !$0.eventID.isEmpty && $0.eventID.utf16.count <= 2048
                  && !$0.references.isEmpty && validReferences($0.references, sources: sources) }) else { return false }
        return CoachDocumentReviewStore.valid(data) && (data.coachState.calendarDrafts ?? []).allSatisfy {
            validReferences($0.documentReferences ?? [], sources: sources)
        }
    }

    /// Called within the same local acknowledgement that marks a draft created.
    /// It neither creates nor looks up an EventKit event.
    static func attach(_ refs: [CoachDocumentReference], to eventID: String, data: inout AppData) -> Bool {
        guard !eventID.isEmpty, eventID.utf16.count <= 2048,
              valid(data), validReferences(refs, sources: data.coachDocuments ?? []) else { return false }
        guard !refs.isEmpty else { return true }
        var links = data.coachDocumentEventLinks ?? []
        if let old = links.first(where: { $0.eventID == eventID }) { return old.references == refs }
        guard links.count < 10_000 else { return false }
        links.append(.init(eventID: eventID, references: refs)); data.coachDocumentEventLinks = links
        return true
    }

    /// Stable app route, never a filesystem path or a provider-supplied URL.
    static func url(sourceID: UUID, page: Int, sources: [CoachDocumentSource]) -> URL? {
        guard CoachDocumentSource.validLibrary(sources),
              CoachDocumentReference(sourceID: sourceID, pages: [page]).isValid(in: sources) else { return nil }
        var route = URLComponents(); route.scheme = "pivot"; route.host = "document"
        route.path = "/" + sourceID.uuidString
        route.queryItems = [.init(name: "page", value: String(page))]
        return route.url
    }
    static func destination(_ url: URL, sources: [CoachDocumentSource]) -> (source: CoachDocumentSource, page: Int)? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false), value.scheme == "pivot",
              value.host == "document", value.user == nil, value.password == nil, value.port == nil,
              value.fragment == nil, value.queryItems?.count == 1,
              let query = value.queryItems?.first, query.name == "page", let text = query.value,
              let page = Int(text), text == String(page), value.path.count == 37,
              let id = UUID(uuidString: String(value.path.dropFirst())),
              let source = sources.first(where: { $0.id == id }),
              CoachDocumentSource.validLibrary(sources),
              CoachDocumentReference(sourceID: id, pages: [page]).isValid(in: sources) else { return nil }
        return (source, page)
    }
}
