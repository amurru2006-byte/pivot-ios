import Foundation
import SwiftUI
import PDFKit
import UIKit

@MainActor
final class PivotStore: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var error: String?
    @Published private(set) var locked = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isLoading = !PreviewMode.enabled
    @Published private(set) var isSaving = false
    @Published private(set) var saveStatus = "Dati salvati"
    let diagnostics = PerformanceDiagnostics()
    @Published private(set) var backupStatus = "Backup esterno non configurato"
    @Published private(set) var lastExternalBackup: Date?
    private let directory: URL
    private let file: URL
    private let documentsDirectory: URL
    private let persistence: FilePersistence
    private lazy var writer = CoalescingWriter<AppData>(write: { [persistence, diagnostics] snapshot in
        let started = ProcessInfo.processInfo.systemUptime
        try await persistence.save(snapshot)
        diagnostics.record("Scrittura dati", seconds: ProcessInfo.processInfo.systemUptime - started)
    }, onResult: { [weak self] pending, error in
        guard let self else { return }
        self.isSaving = pending
        if let error {
            self.saveStatus = "Salvataggio da riprovare"
            self.error = "I dati aggiornati sono ancora in memoria: il salvataggio su disco non è riuscito. Tieni Pivot aperto e premi Riprova nelle Impostazioni. Dettaglio: \(error.localizedDescription)"
        } else {
            self.saveStatus = pending ? "Salvataggio in corso…" : "Dati salvati"
            if !pending { self.writeExternal(self.data) }
        }
    })
    private let backupQueue = DispatchQueue(label: "app.pivot.external-backup", qos: .utility)
    private var pendingExternalBackup: AppData?
    private var externalBackupRunning = false
    private let bookmarkKey = "pivot.externalBackupFolder.v1"
    private let lastBackupKey = "pivot.lastExternalBackup.v1"
    private var backgroundSaveID: UIBackgroundTaskIdentifier = .invalid

    init() {
        var storageName = "Pivot"
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--student-recognition-test") { storageName = "PivotStudentTests" }
        if ProcessInfo.processInfo.arguments.contains("--payment-schedule-test") { storageName = "PivotPaymentTests" }
        if ProcessInfo.processInfo.arguments.contains("--autofill-test") { storageName = "PivotAutofillTests" }
        if ProcessInfo.processInfo.arguments.contains("--training-edit-test") { storageName = "PivotTrainingEditTests" }
        #endif
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(storageName, isDirectory: true)
        file = directory.appendingPathComponent("pivot-data.json")
        documentsDirectory = directory.appendingPathComponent("StudyPDFs", isDirectory: true)
        persistence = FilePersistence(directory: directory)
        lastExternalBackup = UserDefaults.standard.object(forKey: lastBackupKey) as? Date
        if UserDefaults.standard.data(forKey: bookmarkKey) != nil {
            backupStatus = "Cartella configurata; verifica della copia alla prossima modifica"
        }
        guard !PreviewMode.enabled else { return }
        Task {
            let started = ProcessInfo.processInfo.systemUptime
            do { data = try await persistence.load() }
            catch {
                locked = true
                self.error = "Non riesco a leggere lo storico. Non lo sovrascriverò. Ripristina un backup valido. Dettaglio: \(error.localizedDescription)"
            }
            isLoading = false
            diagnostics.record("Caricamento storico", seconds: ProcessInfo.processInfo.systemUptime - started)
            if !locked { applyInitialSettings() }
            #if DEBUG && targetEnvironment(simulator)
            if !locked, ProcessInfo.processInfo.arguments.contains("--student-recognition-test"), data.clients.isEmpty {
                change { $0.clients = [Client(name: "Giulia Rossi", rateCents: 1800)] }
            }
            if !locked, ProcessInfo.processInfo.arguments.contains("--payment-schedule-test"), data.clients.isEmpty {
                let client = Client(id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!, name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly)
                let monday = StudentPayments.week(containing: Date()).start.addingTimeInterval(17 * 3600)
                change { data in
                    data.clients = [client]
                    data.income = [IncomeEntry(clientID: client.id, clientName: client.name, date: monday, minutes: 60, amountCents: 1800, calendarEventID: "payment-test-0")]
                    let event = CalendarItem(id: "payment-test-0", eventIdentifier: "payment-test-0", calendarIdentifier: "interaction", calendarTitle: "Lavoro", title: "Ripetizioni con Giulia Rossi", start: monday.addingTimeInterval(-3600), end: monday, location: "", notes: "", colorHex: "#7EE6CD", isAllDay: false, writable: false, kind: .tutoring)
                    var record = EventRecord(id: event.id, snapshot: event)
                    record.status = .completed; record.tutoringAnswered = true; record.incomeID = data.income[0].id
                    data.records[event.id] = record
                }
            }
            #endif
        }
    }

    private func applyInitialSettings() {
        var next = data
        if !locked {
            if data.settings.notificationPolicyVersion == nil {
                next.settings.notificationPolicyVersion = 1; next.settings.repeatMissedNotifications = false
            }
            let cents = Bundle.main.object(forInfoDictionaryKey: "PivotInitialIncomeCents") as? Int
            let year = Bundle.main.object(forInfoDictionaryKey: "PivotInitialIncomeYear") as? Int
            var ledger = data.ledger ?? AnnualLedger()
            let missingOpening = year.map { ledger.openingCents[String($0)] == nil } ?? false
            if let cents, let year, missingOpening, cents >= 0, (1900...9999).contains(year) {
                ledger.setOpeningTotal(cents, year: year, payments: data.payments)
            }
            if data.ledger == nil || missingOpening { next.ledger = ledger }
            if data.settings.notificationPolicyVersion == nil || data.ledger == nil || missingOpening { change { $0 = next } }
        }
    }

    @discardableResult
    func change(_ edit: (inout AppData) -> Void) -> Bool {
        guard !locked && !isRestoring && !isLoading else { error = "Attendi il caricamento o il ripristino prima di modificare lo storico."; return false }
        var next = data
        edit(&next)
        next.updatedAt = Date()
        data = next
        isSaving = true; saveStatus = "Salvataggio in corso…"
        writer.enqueue(next)
        return true
    }

    @discardableResult func flushPendingWrites() async -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        let ok = await writer.flush()
        diagnostics.record("Salvataggio", seconds: ProcessInfo.processInfo.systemUptime - started)
        return ok
    }

    func saveBeforeBackground() {
        guard !isLoading, backgroundSaveID == .invalid else { return }
        backgroundSaveID = UIApplication.shared.beginBackgroundTask(withName: "Salva Pivot") { [weak self] in self?.endBackgroundSave() }
        Task {
            _ = await flushPendingWrites()
            endBackgroundSave()
        }
    }
    private func endBackgroundSave() {
        guard backgroundSaveID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundSaveID)
        backgroundSaveID = .invalid
    }

    func selectBackupFolder(_ url: URL) {
        guard !isLoading, !isRestoring else { return }
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
        guard !isLoading, !isRestoring else { return }
        guard !locked else { error = "Prima ripristina un backup valido. Il file originale è protetto."; return }
        writeExternal(data)
    }

    private func writeExternal(_ snapshot: AppData) {
        guard UserDefaults.standard.data(forKey: bookmarkKey) != nil else { return }
        pendingExternalBackup = snapshot
        backupStatus = "Aggiornamento della copia esterna…"
        startNextExternalBackup()
    }
    private func startNextExternalBackup() {
        guard !externalBackupRunning, let snapshot = pendingExternalBackup,
              let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        pendingExternalBackup = nil
        externalBackupRunning = true
        // A slow cloud folder retains at most the in-flight and latest snapshots,
        // not a growing queue of complete historical states/PDF exports.
        let pdfDirectory = documentsDirectory
        backupQueue.async { [weak self] in
            let result = Self.performExternalBackup(snapshot, bookmark: bookmark, documents: pdfDirectory)
            DispatchQueue.main.async {
                guard let self else { return }
                self.externalBackupRunning = false
                if UserDefaults.standard.data(forKey: self.bookmarkKey) == bookmark {
                    if let updatedBookmark = result.bookmark { UserDefaults.standard.set(updatedBookmark, forKey: self.bookmarkKey) }
                    if let date = result.date {
                        self.lastExternalBackup = date
                        UserDefaults.standard.set(date, forKey: self.lastBackupKey)
                    }
                    self.backupStatus = self.pendingExternalBackup == nil ? result.status : "Aggiornamento della copia esterna…"
                }
                self.startNextExternalBackup()
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
            let bytes = try BackupCodec.encode(StudyFiles.completeBackup(HealthImport.exportData(snapshot), directory: documents))
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
        guard !isLoading, await flushPendingWrites() else { throw BackupError.invalidData }
        let snapshot = data, sourceFile = file, pdfDirectory = documentsDirectory, isLocked = locked
        return try await Task.detached(priority: .utility) {
            let bytes = isLocked ? try Data(contentsOf: sourceFile) : try BackupCodec.encode(StudyFiles.completeBackup(HealthImport.exportData(snapshot), directory: pdfDirectory))
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Backup Pivot.json")
            try bytes.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return destination
        }.value
    }

    func restore(_ url: URL) async {
        guard !isRestoring, !isLoading else { return }
        isRestoring = true
        defer { isRestoring = false }
        guard await flushPendingWrites() else { return }
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
            try await persistence.save(restored, restoring: true)
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

    func importTrainingPDF(_ url: URL) async throws -> TrainingPlan {
        guard !locked && !isRestoring else { throw BackupError.invalidData }
        let destinationDirectory = documentsDirectory
        return try await Task.detached(priority: .utility) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > StudyFiles.maximumBytes { throw StudyFileError.tooLarge }
            let bytes = try Data(contentsOf: url)
            try StudyFiles.validate(bytes)
            guard let pdf = PDFDocument(data: bytes), !pdf.isLocked, (1...100).contains(pdf.pageCount) else { throw StudyFileError.invalidPDF }
            let payload = try TrainingPDFFormat.parse(pdf.string ?? "")
            let document = StudyDocument(name: url.lastPathComponent, byteCount: bytes.count)
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try bytes.write(to: StudyFiles.url(for: document.id, directory: destinationDirectory), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return TrainingPlan(payload: payload, document: document)
        }.value
    }

    func installTrainingPlan(_ plan: TrainingPlan) throws {
        var library = data.training ?? TrainingLibrary()
        guard library.plans.count < 6 else { throw TrainingError.invalidPlan }
        guard StudyFiles.documents(in: data).reduce(0, { $0 + $1.byteCount }) + (plan.document?.byteCount ?? 0) <= StudyFiles.maximumLibraryBytes else { throw StudyFileError.libraryFull }
        library.plans.append(plan); library.activePlanID = plan.id
        try library.validate()
        guard change({ $0.training = library }) else { throw BackupError.invalidData }
    }

    @discardableResult func saveTraining(_ session: TrainingSession, tips: [String: String], event: CalendarItem?) -> Bool {
        var library = data.training ?? TrainingLibrary()
        let previous = library.sessions.first { $0.id == session.id }
        if let index = library.sessions.firstIndex(where: { $0.id == session.id }) { library.sessions[index] = session }
        else { library.sessions.append(session) }
        for (key, value) in tips { library.tips[key] = value }
        do { try library.validate() }
        catch { self.error = "Controlla carichi e ripetizioni prima di salvare. I dati precedenti sono conservati."; return false }
        return change { data in
            data.training = library
            if let event = event ?? session.calendarEventID.flatMap({ data.records[$0]?.snapshot }) {
                let existing = data.records[event.id]
                let record = existing ?? EventRecord(id: event.id, snapshot: event)
                data.records[event.id] = TrainingTiming.merging(session, previous: existing == nil ? nil : previous, into: record)
            }
        }
    }

    func trainingExportURL(_ session: TrainingSession) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Allenamento-Pivot-\(PivotDate.key(session.start))-\(session.id.uuidString.prefix(8)).txt")
        let library = data.training ?? TrainingLibrary()
        return try await Task.detached(priority: .utility) {
            try Data(TrainingExport.text(session, library: library).utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        }.value
    }

    func incomeExcelURL(year: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Registro-Pivot-\(year).xlsx")
        let snapshot = data
        return try await Task.detached(priority: .utility) {
            try LedgerExcel.make(data: snapshot, year: year).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        }.value
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
