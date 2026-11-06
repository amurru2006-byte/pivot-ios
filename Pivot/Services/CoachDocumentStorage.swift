import Foundation

/// Original files are immutable. New UUID paths may leave an unreferenced copy
/// after interruption, but cannot damage files referenced by an older snapshot.
enum CoachDocumentStorage {
    enum Failure: LocalizedError {
        case exists, unavailable, changed, busy, notSaved
        var errorDescription: String? {
            switch self {
            case .exists: return "La copia locale è già presente. Non l’ho sostituita: riprova l’importazione."
            case .unavailable: return "Non riesco a salvare o aprire la copia locale. L’originale non è stato modificato."
            case .changed: return "La copia locale manca o è diversa dall’originale verificato. Importa nuovamente lo stesso documento per recuperarla."
            case .busy: return "Attendi il caricamento, l’importazione o il ripristino in corso prima di aggiungere un documento."
            case .notSaved: return "I dati aggiornati sono ancora in memoria, ma il salvataggio dell’archivio non è riuscito. Tieni Pivot aperto e riprova."
            }
        }
    }
    static func validate(_ source: CoachDocumentSource, bytes: Data) throws {
        guard source.matches(bytes) else { throw Failure.changed }
        let inspected = try CoachDocumentReader.pdf(bytes, name: source.document.name, kind: source.kind, now: source.importedAt)
        guard inspected.source.pageCount == source.pageCount else { throw Failure.changed }
    }
    static func writeNew(_ source: CoachDocumentSource, bytes: Data, directory: URL) throws {
        try Task.checkCancellation()
        try validate(source, bytes: bytes)
        let destination = StudyFiles.url(for: source.document.id, directory: directory)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.exists }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Do not combine .atomic with .withoutOverwriting. This unpublished
            // UUID is registered only after the complete, synchronized write.
            try bytes.write(to: destination, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.synchronize()
        } catch { throw Failure.unavailable }
        try Task.checkCancellation()
    }
    static func verifiedBytes(_ source: CoachDocumentSource, directory: URL) throws -> Data {
        try Task.checkCancellation()
        guard source.isValid else { throw Failure.changed }
        do {
            // Stream through the bounded reader; do not allocate an arbitrary
            // replacement file before checking the established 10 MB limit.
            let value = try CoachDocumentReader.readFile(StudyFiles.url(for: source.document.id, directory: directory))
            try validate(source, bytes: value.bytes)
            try Task.checkCancellation()
            return value.bytes
        } catch is CancellationError { throw CancellationError() }
        catch { throw Failure.changed }
    }
}
