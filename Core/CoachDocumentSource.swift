import Foundation
import CryptoKit

/// LOCAL source identity is stable across restores. The immutable physical PDF
/// has a separate StudyDocument ID so restore can allocate a fresh file safely.
/// Photos will be rendered to PDF locally, without their original EXIF metadata.
struct CoachDocumentSource: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case pdf, photo }
    var id = UUID()
    var document: StudyDocument
    var kind: Kind
    var pageCount: Int
    var sha256: String
    var importedAt: Date

    var isValid: Bool {
        !document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && document.name.count <= 200
            && !document.name.contains(where: { "/\\".contains($0) })
            && document.name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && (1...StudyFiles.maximumBytes).contains(document.byteCount)
            && (1...500).contains(pageCount)
            && sha256.count == 64 && sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
            && CoachPlanningSession.validDate(importedAt)
    }
    func matches(_ bytes: Data) -> Bool {
        guard isValid, bytes.count == document.byteCount, (try? StudyFiles.validate(bytes)) != nil else { return false }
        return Self.digest(bytes) == sha256
    }
    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    /// Does not parse or render the PDF. The iOS importer must additionally use
    /// PDFKit to verify its actual page count and reject locked/damaged files.
    static func validLibrary(_ sources: [Self]) -> Bool {
        sources.count <= 128 && sources.allSatisfy(\.isValid)
            && Set(sources.map(\.id)).count == sources.count
            && Set(sources.map { $0.document.id }).count == sources.count
            && sources.reduce(0, { $0 + $1.document.byteCount }) <= StudyFiles.maximumLibraryBytes
    }
}

/// A bounded, explicit selection of pages. No silent whole-document coverage.
/// These values do not grant permission to send their contents anywhere.
struct CoachDocumentPage: Codable, Equatable {
    enum Reading: String, Codable { case text, ocr, unreadable }
    var sourceID: UUID
    var number: Int
    var text: String
    var reading: Reading
    var ocrConfidence: Double? = nil

    var isValid: Bool {
        guard (1...500).contains(number), text.utf16.count <= 20_000,
              ocrConfidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { return false }
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch reading {
        case .text: return !empty && ocrConfidence == nil
        case .ocr: return !empty && ocrConfidence != nil
        case .unreadable: return empty && ocrConfidence == nil
        }
    }
    var contentDigest: String { CoachDocumentSource.digest(Data(text.utf8)) }
}

/// A citation proves that a quotation is present, not that an interpretation of
/// its dates or meaning is correct. The latter still requires native review.
struct CoachDocumentCitation: Codable, Equatable {
    var sourceID: UUID
    var page: Int
    var quote: String
    func isGrounded(in packet: CoachDocumentPacket) -> Bool {
        guard packet.isValid else { return false }
        let quote = Self.normalized(quote)
        guard !quote.isEmpty, quote.utf16.count <= 800,
              let source = packet.sources.first(where: { $0.id == sourceID }), page <= source.pageCount,
              let value = packet.pages.first(where: { $0.sourceID == sourceID && $0.number == page }),
              value.reading != .unreadable else { return false }
        return Self.normalized(value.text).contains(quote)
    }
    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Request-bound LOCAL snapshot, deliberately not a provider DTO or credential.
/// Provider aliases and explicit outbound consent will be separate boundaries.
struct CoachDocumentPacket: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt: Date
    var instruction: String
    var sources: [CoachDocumentSource]
    var pages: [CoachDocumentPage]
    private struct PageKey: Hashable { var source: UUID; var number: Int }

    var isValid: Bool {
        guard CoachPlanningSession.validDate(createdAt),
              !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              instruction.utf16.count <= 4000,
              (1...6).contains(sources.count), CoachDocumentSource.validLibrary(sources),
              (1...40).contains(pages.count), pages.allSatisfy(\.isValid),
              Set(pages.map { PageKey(source: $0.sourceID, number: $0.number) }).count == pages.count,
              pages.reduce(0, { $0 + $1.text.utf16.count }) <= 120_000,
              sources.allSatisfy({ $0.importedAt <= createdAt }) else { return false }
        return sources.allSatisfy { source in pages.contains { $0.sourceID == source.id } }
            && pages.allSatisfy { page in sources.contains { $0.id == page.sourceID && page.number <= $0.pageCount } }
    }
    func isCurrent(in library: [CoachDocumentSource]) -> Bool {
        guard isValid, CoachDocumentSource.validLibrary(library) else { return false }
        return sources.allSatisfy { source in library.first(where: { $0.id == source.id }) == source }
    }
    var unreadablePages: Int { pages.filter { $0.reading == .unreadable }.count }
    func coverage(for sourceID: UUID) -> String? {
        guard isValid, let source = sources.first(where: { $0.id == sourceID }) else { return nil }
        let selected = pages.filter { $0.sourceID == sourceID }.map(\.number).sorted()
        let failed = pages.filter { $0.sourceID == sourceID && $0.reading == .unreadable }.count
        return "Pagine selezionate: \(selected.map(String.init).joined(separator: ", ")) di \(source.pageCount)."
            + (failed > 0 ? " \(failed) pagine non leggibili: il contenuto non è stato ricostruito." : "")
    }
}
