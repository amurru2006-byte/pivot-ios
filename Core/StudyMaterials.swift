import Foundation

struct StudyDocument: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var byteCount: Int
}

struct StudySession: Codable {
    var objectives: String = ""
    var exercises: String = ""
    var documents: [StudyDocument] = []
}

enum StudyFileError: LocalizedError {
    case invalidPDF, tooLarge, tooMany, libraryFull, missingFile, invalidBackup
    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Il file non è un PDF leggibile. Scegli un altro documento."
        case .tooLarge: return "Il PDF supera 10 MB. Usa una versione più leggera."
        case .tooMany: return "Puoi allegare fino a 6 PDF per sessione."
        case .libraryFull: return "I PDF dello storico supererebbero 50 MB. Rimuovi un allegato dopo averne conservato una copia."
        case .missingFile: return "Manca un PDF dello storico. Il backup completo non è stato sovrascritto. Importa di nuovo il documento."
        case .invalidBackup: return "I PDF del backup sono mancanti o danneggiati. Nessun dato è stato sostituito."
        }
    }
}

enum StudyFiles {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumDocuments = 6
    static let maximumLibraryBytes = 50 * 1024 * 1024
    static func validate(_ bytes: Data) throws {
        guard bytes.count <= maximumBytes else { throw StudyFileError.tooLarge }
        guard bytes.starts(with: Data("%PDF-".utf8)), bytes.suffix(2048).range(of: Data("%%EOF".utf8)) != nil else { throw StudyFileError.invalidPDF }
    }
    static func documents(in data: AppData) -> [StudyDocument] {
        data.records.values.flatMap { $0.study?.documents ?? [] } + (data.training?.plans.map(\.document) ?? [])
    }
    static func url(for id: UUID, directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("pdf")
    }
    static func validateBackup(_ data: AppData, requireFiles: Bool = false) throws {
        let documents = documents(in: data)
        guard data.records.values.allSatisfy({ ($0.study?.documents.count ?? 0) <= maximumDocuments }),
              documents.allSatisfy({ !$0.name.isEmpty && $0.byteCount > 0 && $0.byteCount <= maximumBytes }),
              Set(documents.map(\.id)).count == documents.count else { throw StudyFileError.invalidBackup }
        guard documents.reduce(0, { $0 + $1.byteCount }) <= maximumLibraryBytes else { throw StudyFileError.libraryFull }
        guard let files = data.studyPDFs else {
            if requireFiles && !documents.isEmpty { throw StudyFileError.invalidBackup }
            return
        }
        guard Set(files.keys) == Set(documents.map { $0.id.uuidString }) else { throw StudyFileError.invalidBackup }
        for doc in documents {
            guard let bytes = files[doc.id.uuidString], bytes.count == doc.byteCount else { throw StudyFileError.invalidBackup }
            try validate(bytes)
        }
    }
    static func completeBackup(_ data: AppData, directory: URL) throws -> AppData {
        var backup = data
        var files: [String: Data] = [:]
        for doc in documents(in: data) {
            let file = url(for: doc.id, directory: directory)
            guard let bytes = try? Data(contentsOf: file), bytes.count == doc.byteCount else { throw StudyFileError.missingFile }
            try validate(bytes)
            files[doc.id.uuidString] = bytes
        }
        backup.studyPDFs = files.isEmpty ? nil : files
        try validateBackup(backup, requireFiles: true)
        return backup
    }
    // Restoring to new immutable IDs protects PDFs belonging to the pre-restore history.
    static func installBackup(_ data: AppData, directory: URL) throws -> AppData {
        try validateBackup(data, requireFiles: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var restored = data
        var restoredDocumentIDs: [UUID: UUID] = [:]
        for key in Array(restored.records.keys) {
            guard var record = restored.records[key], var session = record.study else { continue }
            for index in session.documents.indices {
                let old = session.documents[index].id
                guard let bytes = data.studyPDFs?[old.uuidString] else { throw StudyFileError.invalidBackup }
                let fresh = UUID()
                try bytes.write(to: url(for: fresh, directory: directory), options: .atomic)
                session.documents[index].id = fresh
                restoredDocumentIDs[old] = fresh
            }
            record.study = session
            restored.records[key] = record
        }
        // Drafts refer to the same files as saved sessions. Keep them usable after ID-safe restore.
        for key in Array((restored.activityDrafts ?? [:]).keys) {
            guard var draft = restored.activityDrafts?[key], var session = draft.record.study else { continue }
            session.documents = session.documents.compactMap { document in
                guard let fresh = restoredDocumentIDs[document.id] else { return nil }
                var updated = document; updated.id = fresh; return updated
            }
            draft.record.study = session; restored.activityDrafts?[key] = draft
        }
        if var library = restored.training {
            for index in library.plans.indices {
                let old = library.plans[index].document.id
                guard let bytes = data.studyPDFs?[old.uuidString] else { throw StudyFileError.invalidBackup }
                let fresh = UUID()
                try bytes.write(to: url(for: fresh, directory: directory), options: .atomic)
                library.plans[index].document.id = fresh
            }
            restored.training = library
        }
        restored.studyPDFs = nil
        return restored
    }
}
