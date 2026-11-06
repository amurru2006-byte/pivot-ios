import Foundation
import PDFKit
import UIKit
import Vision
import ImageIO

/// No network or Calendar writes. Caller owns import persistence and outbound
/// consent; this reader returns only the explicitly requested pages.
enum CoachDocumentReader {
    struct Prepared { var source: CoachDocumentSource; var bytes: Data }
    enum Failure: LocalizedError {
        case invalid, selection, pageTooLong(Int), selectionTooLong, image
        var errorDescription: String? {
            switch self {
            case .invalid: return "Il documento è danneggiato, protetto o supera 500 pagine. Non ne ho ricostruito il contenuto."
            case .selection: return "Scegli da 1 a 40 pagine esistenti, senza duplicati. Le altre non saranno lette."
            case .pageTooLong(let page): return "La pagina \(page) contiene troppo testo per questa lettura. Nessuna parte è stata tagliata o inviata."
            case .selectionTooLong: return "Le pagine selezionate contengono troppo testo. Scegline meno: nessuna parte è stata tagliata o inviata."
            case .image: return "Non riesco a leggere questa immagine. Usa una foto o uno screenshot più nitido e di massimo 20 MB."
            }
        }
    }
    static func pdf(_ bytes: Data, name: String, kind: CoachDocumentSource.Kind = .pdf, now: Date = Date()) throws -> Prepared {
        try StudyFiles.validate(bytes)
        guard let pdf = PDFDocument(data: bytes), !pdf.isLocked, (1...500).contains(pdf.pageCount),
              (0..<pdf.pageCount).allSatisfy({ pdf.page(at: $0) != nil }) else { throw Failure.invalid }
        let source = CoachDocumentSource(document: .init(name: name, byteCount: bytes.count), kind: kind,
            pageCount: pdf.pageCount, sha256: CoachDocumentSource.digest(bytes), importedAt: now)
        guard source.isValid else { throw Failure.invalid }
        return .init(source: source, bytes: bytes)
    }
    static func readFile(_ url: URL) throws -> Prepared {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL, let stream = InputStream(url: url) else { throw Failure.invalid }
        stream.open(); defer { stream.close() }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw Failure.invalid }
            if count == 0 { break }
            guard bytes.count + count <= StudyFiles.maximumBytes else { throw StudyFileError.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return try pdf(bytes, name: url.lastPathComponent)
    }
    /// A visual reproduction, not an exact copy of the original image file.
    /// ImageIO applies orientation while generating a bounded thumbnail. The new
    /// PDF embeds pixels only, without original GPS/EXIF or photo-library IDs.
    static func photo(_ bytes: Data, now: Date = Date()) throws -> Prepared {
        guard !bytes.isEmpty, bytes.count <= 20 * 1024 * 1024,
              let input = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(input) == 1,
              let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3000
              ] as CFDictionary), image.width > 0, image.height > 0 else { throw Failure.image }
        let size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let format = UIGraphicsPDFRendererFormat(); format.documentInfo = [:]
        let rendered = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size), format: format).pdfData { context in
            context.beginPage(); UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return try pdf(rendered, name: "Foto allegata.pdf", kind: .photo, now: now)
    }
    static func pages(_ source: CoachDocumentSource, bytes: Data, numbers: [Int], forceOCR: Bool = false) throws -> [CoachDocumentPage] {
        guard source.matches(bytes), let pdf = PDFDocument(data: bytes), !pdf.isLocked,
              pdf.pageCount == source.pageCount else { throw Failure.invalid }
        guard (1...40).contains(numbers.count), Set(numbers).count == numbers.count,
              numbers.allSatisfy({ (1...source.pageCount).contains($0) }) else { throw Failure.selection }
        var result: [CoachDocumentPage] = [], total = 0
        for number in numbers.sorted() {
            try Task.checkCancellation()
            let value: CoachDocumentPage = try autoreleasepool {
                guard let page = pdf.page(at: number - 1) else { throw Failure.invalid }
                let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !forceOCR && !text.isEmpty {
                    guard text.utf16.count <= 20_000 else { throw Failure.pageTooLong(number) }
                    return .init(sourceID: source.id, number: number, text: text, reading: .text)
                }
                guard let image = page.thumbnail(of: CGSize(width: 2048, height: 2048), for: .mediaBox).cgImage else {
                    return .init(sourceID: source.id, number: number, text: "", reading: .unreadable)
                }
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
                do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
                catch { return .init(sourceID: source.id, number: number, text: "", reading: .unreadable) }
                let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
                let recognized = candidates.map(\.string).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !recognized.isEmpty else { return .init(sourceID: source.id, number: number, text: "", reading: .unreadable) }
                guard recognized.utf16.count <= 20_000 else { throw Failure.pageTooLong(number) }
                // Average OCR confidence is a warning signal, never a proof of
                // completeness, date accuracy or table/column reconstruction.
                let confidence = candidates.reduce(0.0) { $0 + Double($1.confidence) } / Double(candidates.count)
                return .init(sourceID: source.id, number: number, text: recognized, reading: .ocr, ocrConfidence: confidence)
            }
            try Task.checkCancellation()
            total += value.text.utf16.count
            guard total <= 120_000 else { throw Failure.selectionTooLong }
            result.append(value)
        }
        return result
    }
}
