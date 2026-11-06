import Foundation

enum CoachDocumentReplyFile {
    enum Failure: LocalizedError {
        case invalid, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalid: return "Non riesco a leggere la risposta. Scegli il file JSON o incolla volontariamente il suo testo."
            case .tooLarge: return "La risposta supera 64.000 byte. Non ne ho importata solo una parte: chiedi una risposta più breve."
            }
        }
    }
    static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL, let stream = InputStream(url: url) else { throw Failure.invalid }
        stream.open(); defer { stream.close() }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            try Task.checkCancellation()
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw Failure.invalid }
            if count == 0 { break }
            guard bytes.count + count <= 64_000 else { throw Failure.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        guard !bytes.isEmpty, String(data: bytes, encoding: .utf8) != nil else { throw Failure.invalid }
        return bytes
    }
}
