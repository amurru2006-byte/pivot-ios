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
        return (data.coachState.calendarDrafts ?? []).allSatisfy {
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
