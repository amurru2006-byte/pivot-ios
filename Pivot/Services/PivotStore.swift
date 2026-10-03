import Foundation
import SwiftUI
import PDFKit

@MainActor
final class PivotStore: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var error: String?
    @Published private(set) var locked = false
    @Published private(set) var isRestoring = false
    @Published private(set) var backupStatus = "Backup esterno non configurato"
    @Published private(set) var lastExternalBackup: Date?
    private let directory: URL
    private let file: URL
    private let documentsDirectory: URL
    private let backupQueue = DispatchQueue(label: "app.pivot.external-backup", qos: .utility)
    private let bookmarkKey = "pivot.externalBackupFolder.v1"
    private let lastBackupKey = "pivot.lastExternalBackup.v1"

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pivot", isDirectory: true)
        file = directory.appendingPathComponent("pivot-data.json")
        documentsDirectory = directory.appendingPathComponent("StudyPDFs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                data = try BackupCodec.decode(Data(contentsOf: file))
            }
        } catch {
            locked = true
            self.error = "Non riesco a leggere lo storico. Non lo sovrascriverò. Esporta il file dall'app File o ripristina un backup valido. Dettaglio: \(error.localizedDescription)"
        }
        if !locked {
            let cents = Bundle.main.object(forInfoDictionaryKey: "PivotInitialIncomeCents") as? Int
            let year = Bundle.main.object(forInfoDictionaryKey: "PivotInitialIncomeYear") as? Int
            var ledger = data.ledger ?? AnnualLedger()
            let missingOpening = year.map { ledger.openingCents[String($0)] == nil } ?? false
            if let cents, let year, missingOpening, cents >= 0, (1900...9999).contains(year) {
                ledger.setOpeningTotal(cents, year: year, payments: data.payments)
            }
            if data.ledger == nil || missingOpening { change { $0.ledger = ledger } }
        }
        lastExternalBackup = UserDefaults.standard.object(forKey: lastBackupKey) as? Date
        if UserDefaults.standard.data(forKey: bookmarkKey) != nil {
            backupStatus = "Cartella configurata; verifica della copia alla prossima modifica"
        }
    }

    @discardableResult
    func change(_ edit: (inout AppData) -> Void) -> Bool {
        guard !locked && !isRestoring else { error = "Salvataggio bloccato durante il ripristino o per proteggere lo storico originale."; return false }
        var next = data
        edit(&next)
        next.updatedAt = Date()
        do {
            let bytes = try BackupCodec.encode(next)
            if FileManager.default.fileExists(atPath: file.path) {
                let old = try Data(contentsOf: file)
                try old.write(to: directory.appendingPathComponent("previous.json"), options: .atomic)
            }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = next
            writeExternal(next)
            return true
        } catch { self.error = "Modifica non salvata: \(error.localizedDescription)"; return false }
    }

    func selectBackupFolder(_ url: URL) {
        guard !locked else { error = "Prima ripristina un backup valido. Il file originale è protetto."; return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try Self.validateExternalFolder(url)
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            writeExternal(data)
        } catch { self.error = "Cartella di backup non configurata: \(error.localizedDescription)" }
    }

    func backupNow() {
        guard !locked else { error = "Prima ripristina un backup valido. Il file originale è protetto."; return }
        writeExternal(data)
    }

    private func writeExternal(_ snapshot: AppData) {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        backupStatus = "Aggiornamento della copia esterna…"
        // Cloud-backed folders can stall on file hydration. Keep all their I/O
        // off the UI queue, in write order, including the backup made on upgrade.
        let pdfDirectory = documentsDirectory
        backupQueue.async { [weak self] in
            let result = Self.performExternalBackup(snapshot, bookmark: bookmark, documents: pdfDirectory)
            DispatchQueue.main.async {
                guard let self else { return }
                if let updatedBookmark = result.bookmark { UserDefaults.standard.set(updatedBookmark, forKey: self.bookmarkKey) }
                if let date = result.date {
                    self.lastExternalBackup = date
                    UserDefaults.standard.set(date, forKey: self.lastBackupKey)
                }
                self.backupStatus = result.status
            }
        }
    }
    private struct BackupResult {
        var status: String
        var date: Date? = nil
        var bookmark: Data? = nil
    }
    private nonisolated static func performExternalBackup(_ snapshot: AppData, bookmark: Data, documents: URL) -> BackupResult {
        do {
            let bytes = try BackupCodec.encode(StudyFiles.completeBackup(snapshot, directory: documents))
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            try validateExternalFolder(folder)
            let refreshedBookmark = stale ? try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            let destination = folder.appendingPathComponent("Backup Pivot.json")
            if FileManager.default.fileExists(atPath: destination.path) {
                let previous = try Data(contentsOf: destination)
                if (try? BackupCodec.decode(previous)) != nil {
                    try previous.write(to: folder.appendingPathComponent("Backup Pivot precedente.json"), options: .atomic)
                }
            }
            try bytes.write(to: destination, options: .atomic)
            _ = try BackupCodec.decode(Data(contentsOf: destination))
            return BackupResult(status: "Copia esterna scritta e verificata. La sincronizzazione iCloud è gestita da iOS.", date: Date(), bookmark: refreshedBookmark)
        } catch {
            return BackupResult(status: "ATTENZIONE: copia esterna non aggiornata. \(error.localizedDescription)")
        }
    }

    private nonisolated static func validateExternalFolder(_ url: URL) throws {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let container = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
        guard path != container && !path.hasPrefix(container + "/") else {
            throw NSError(domain: "PivotBackup", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Scegli una cartella in iCloud Drive o esterna a Pivot. La cartella interna sparirebbe cancellando l'app."])
        }
    }

    func exportURL() async throws -> URL {
        let snapshot = data, sourceFile = file, pdfDirectory = documentsDirectory, isLocked = locked
        return try await Task.detached(priority: .utility) {
            let bytes = isLocked ? try Data(contentsOf: sourceFile) : try BackupCodec.encode(StudyFiles.completeBackup(snapshot, directory: pdfDirectory))
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Backup Pivot.json")
            try bytes.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return destination
        }.value
    }

    func restore(_ url: URL) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        let pdfDirectory = documentsDirectory
        do {
            let restored = try await Task.detached(priority: .utility) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let decoded = try BackupCodec.decode(Data(contentsOf: url))
                for bytes in (decoded.studyPDFs ?? [:]).values {
                    guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0, !pdf.isLocked else { throw StudyFileError.invalidBackup }
                }
                return try StudyFiles.installBackup(decoded, directory: pdfDirectory)
            }.value
            let bytes = try BackupCodec.encode(restored)
            if FileManager.default.fileExists(atPath: file.path) {
                let old = try Data(contentsOf: file)
                let archive = directory.appendingPathComponent("before-restore-\(Int(Date().timeIntervalSince1970)).json")
                try old.write(to: archive, options: .atomic)
            }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = restored
            locked = false
            error = nil
            writeExternal(restored)
        } catch { self.error = "Ripristino non eseguito: \(error.localizedDescription)" }
    }

    func importStudyPDF(_ url: URL) async throws -> StudyDocument {
        guard !locked && !isRestoring else { throw BackupError.invalidData }
        let destinationDirectory = documentsDirectory
        return try await Task.detached(priority: .utility) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > StudyFiles.maximumBytes { throw StudyFileError.tooLarge }
            let bytes = try Data(contentsOf: url)
            try StudyFiles.validate(bytes)
            guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0, !pdf.isLocked else { throw StudyFileError.invalidPDF }
            let document = StudyDocument(name: url.lastPathComponent, byteCount: bytes.count)
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try bytes.write(to: StudyFiles.url(for: document.id, directory: destinationDirectory), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return document
        }.value
    }
    func studyPDFURL(_ document: StudyDocument) throws -> URL {
        let url = StudyFiles.url(for: document.id, directory: documentsDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { throw StudyFileError.missingFile }
        return url
    }

    func incomeExcelURL(year: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Registro-Pivot-\(year).xlsx")
        try LedgerExcel.make(data: data, year: year).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    func record(for event: CalendarItem) -> EventRecord {
        data.records[event.id] ?? EventRecord(id: event.id, snapshot: event)
    }
    func rule(for event: CalendarItem) -> EventRule { data.rules[event.id] ?? .defaultRule(for: event) }
    func saveRecord(_ record: EventRecord) {
        var updated = record
        updated.updatedAt = Date()
        change { $0.records[updated.id] = updated }
    }
}
