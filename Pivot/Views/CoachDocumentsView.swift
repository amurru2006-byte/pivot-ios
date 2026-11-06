import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct CoachDocumentsView: View {
    @EnvironmentObject private var store: PivotStore
    @State private var filePicker = false
    @State private var camera = false
    @State private var photo: PhotosPickerItem?
    @State private var selections: [UUID: String] = [:]
    @State private var instruction = ""
    @State private var forceOCR = false
    @State private var busy = false
    @State private var status: String?
    @State private var packet: CoachDocumentPacket?
    @State private var viewer: CoachDocumentDestination?
    @FocusState private var instructionFocused: Bool
    private var sources: [CoachDocumentSource] { store.data.coachDocuments ?? [] }
    private var unavailable: Bool { busy || store.locked || store.isLoading || store.isRestoring || store.isImportingCoachDocument }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            // Keep import/read feedback at the beginning of the list instead
            // of virtualizing it below the newly inserted document rows.
            if let status { Section { Text(status).accessibilityIdentifier("coach-document-status").id("coach-document-feedback") } }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--interaction-test"),
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_DOCUMENT_ID"] ?? "") != nil {
                Section("Prove sintetiche") {
                    Text("\(sources.count) fonti salvate").accessibilityIdentifier("coach-document-library-audit")
                    Button("Importa PDF sintetico QA") { Task { await importFixture(invalid: false) } }
                        .accessibilityIdentifier("coach-document-import-qa").disabled(unavailable)
                    Button("Prova PDF incoerente QA") { Task { await importFixture(invalid: true) } }
                        .accessibilityIdentifier("coach-document-invalid-qa").disabled(unavailable)
                }
            }
            #endif
            Section {
                Text("Le copie restano in Pivot e nel tuo backup cifrato. Importare o leggere una pagina non la invia a un’IA e non crea eventi.")
                    .font(.subheadline)
                Button { filePicker = true } label: { Label("Aggiungi PDF o immagine", systemImage: "doc.badge.plus") }
                    .accessibilityIdentifier("coach-document-file")
                PhotosPicker(selection: $photo, matching: .images) { Label("Scegli foto", systemImage: "photo") }
                    .accessibilityIdentifier("coach-document-photo")
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { camera = true } label: { Label("Scatta foto", systemImage: "camera") }
                        .accessibilityIdentifier("coach-document-camera")
                }
                Text("PDF fino a 10 MB e 500 pagine. Le foto diventano copie PDF senza i metadati originali. Libreria complessiva: 50 MB.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(unavailable)
            Section("Documenti salvati") {
                if sources.isEmpty { Text("Aggiungi uno o più documenti per iniziare.").foregroundStyle(.secondary) }
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { selections[source.id] != nil }, set: { selected in
                            if selected { selections[source.id] = "1" } else { selections.removeValue(forKey: source.id) }
                            packet = nil
                        })) { Text(source.document.name) }
                        .accessibilityIdentifier("coach-document-select-" + source.id.uuidString)
                        .disabled(unavailable || (selections[source.id] == nil && selections.count >= 6))
                        Text("\(source.pageCount) pagine · \(source.kind == .photo ? "Copia da foto" : "PDF originale")")
                            .font(.caption).foregroundStyle(.secondary)
                        if selections[source.id] != nil {
                            TextField("Pagine, ad esempio 1-3, 5", text: Binding(get: { selections[source.id] ?? "" }, set: {
                                selections[source.id] = $0; packet = nil
                            })).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(unavailable)
                                .accessibilityIdentifier("coach-document-pages-" + source.id.uuidString)
                            if CoachDocumentPageSelection.parse(selections[source.id] ?? "", pageCount: source.pageCount) == nil {
                                Text("Indica pagine esistenti, senza sovrapposizioni: per esempio 1-3, 5. Massimo 40.").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Button("Apri originale") { viewer = .init(sourceID: source.id) }.disabled(unavailable)
                    }.padding(.vertical, 4)
                }
            }
            if let reviews = store.data.coachDocumentReviews, !reviews.isEmpty {
                Section("Letture e proposte salvate") {
                    ForEach(reviews.sorted { $0.updatedAt > $1.updatedAt }) { batch in
                        NavigationLink { CoachDocumentReviewView(batchID: batch.id) } label: {
                            VStack(alignment: .leading) {
                                Text(batch.packet.instruction).lineLimit(2)
                                Text("\(batch.events.count) proposte · \(batch.stagedProposalIDs.count) bozze preparate")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("coach-document-review-" + batch.id.uuidString)
                    }
                }
            }
            Section("Lettura selezionata") {
                TextField("Cosa vuoi ricavare da queste pagine?", text: $instruction, axis: .vertical)
                    .accessibilityIdentifier("coach-document-instruction")
                    .focused($instructionFocused)
                    .lineLimit(2...6).disabled(unavailable)
                    .onChange(of: instruction) { _, _ in packet = nil }
                Toggle("Rileggi con OCR anche il testo già presente", isOn: $forceOCR).disabled(unavailable)
                    .onChange(of: forceOCR) { _, _ in packet = nil }
                Text("Scegli fino a 6 fonti e 40 pagine in totale. L’OCR può sbagliare: controlla nomi, anni, date e orari nell’originale.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Leggi le pagine selezionate") { Task { await readSelected() } }
                    .disabled(unavailable || selections.isEmpty || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("coach-document-read")
            }
            if busy { ProgressView("Elaborazione locale…") }
            if let packet {
                Section("Controlla la lettura") {
                    ForEach(packet.sources) { source in
                        Text(source.document.name).font(.headline)
                        Text(packet.coverage(for: source.id) ?? "").font(.caption)
                        ForEach(packet.pages.filter { $0.sourceID == source.id }, id: \.number) { page in
                            DisclosureGroup("Pagina \(page.number) · \(page.reading == .ocr ? "OCR" : page.reading == .unreadable ? "Non leggibile" : "Testo PDF")") {
                                Text(page.text.isEmpty ? "Nessun testo leggibile. Non ho ricostruito questa pagina." : page.text)
                                    .font(.callout).textSelection(.enabled)
                                Button("Verifica nell’originale") { viewer = .init(sourceID: source.id, page: page.number) }
                            }
                        }
                    }
                    Text("Le proposte locali sono nella lettura salvata. Nessun evento è stato creato: controlla gli originali prima di preparare le bozze.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: status) { _, value in
            if value != nil { proxy.scrollTo("coach-document-feedback", anchor: .top) }
        }
        }
        .navigationTitle("Foto e documenti")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fine") { instructionFocused = false }.accessibilityIdentifier("coach-document-keyboard-done")
            }
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await importFiles(urls) }
            case .failure(let error): status = error.localizedDescription
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                guard !unavailable else { return }
                busy = true; status = nil; defer { busy = false; photo = nil }
                do {
                    guard let transferred = try await item.loadTransferable(type: CoachDocumentPhotoTransfer.self) else { throw CoachDocumentReader.Failure.image }
                    let prepared = try await Task.detached(priority: .utility) { try CoachDocumentReader.photo(transferred.bytes) }.value
                    let source = try await store.importCoachDocument(prepared)
                    status = "Salvato: \(source.document.name). Scegli le pagine da leggere."
                } catch { status = error.localizedDescription }
            }
        }
        .sheet(isPresented: $camera) {
            CoachDocumentCamera { bytes in
                camera = false
                guard let bytes else { return }
                Task { await importPhoto(bytes) }
            }.ignoresSafeArea()
        }
        .sheet(item: $viewer) { CoachDocumentViewer(destination: $0) }
        .onChange(of: store.data.coachDocuments) { _, _ in
            // Restores/repairs invalidate old page snapshots; never keep reading
            // a stale physical file or silently choose a new source for it.
            if let packet, !packet.isCurrent(in: sources) { self.packet = nil }
            selections = selections.filter { id, _ in sources.contains { $0.id == id } }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    @MainActor private func importFixture(invalid: Bool) async {
        guard !unavailable, ProcessInfo.processInfo.arguments.contains("--interaction-test"),
              UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_DOCUMENT_ID"] ?? "") != nil else { return }
        busy = true; status = nil; defer { busy = false }
        do {
            let bytes: Data
            if let existing = sources.first { bytes = try await store.coachDocumentBytes(existing.id) }
            else {
                bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 500, height: 700)).pdfData { context in
                    let first = ProcessInfo.processInfo.arguments.contains("--document-timed-test")
                        ? "LABORATORY QA 2030-01-14 09:00-11:00" : "LABORATORY QA 2030-01-14"
                    for text in [first, "SECOND PAGE QA 2030-01-15"] {
                        context.beginPage()
                        (text as NSString).draw(at: CGPoint(x: 20, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
                    }
                }
            }
            var prepared = try CoachDocumentReader.pdf(bytes, name: "Documento QA.pdf")
            if invalid { prepared.source.pageCount += 1 }
            _ = try await store.importCoachDocument(prepared)
            status = "Documento QA salvato senza duplicati."
        } catch { status = "Importazione QA interrotta: " + error.localizedDescription }
    }
    #endif

    @MainActor private func importFiles(_ urls: [URL]) async {
        guard !unavailable else { return }
        guard (1...6).contains(urls.count) else { status = "Scegli da 1 a 6 file per volta. Non ho importato una selezione parziale."; return }
        busy = true; status = nil; defer { busy = false }
        var saved = 0
        do {
            for url in urls {
                let prepared = try await Task.detached(priority: .utility) {
                    if url.pathExtension.lowercased() == "pdf" { return try CoachDocumentReader.readFile(url) }
                    return try CoachDocumentReader.photo(CoachDocumentPhotoTransfer.read(url))
                }.value
                _ = try await store.importCoachDocument(prepared); saved += 1
            }
            status = "\(saved) file elaborati. Le copie identiche già presenti sono state riutilizzate, senza duplicarle."
        } catch {
            status = "\(saved) file elaborati prima dell’interruzione. \(error.localizedDescription) Le fonti già salvate restano disponibili."
        }
    }
    @MainActor private func importPhoto(_ bytes: Data) async {
        guard !unavailable else { return }
        busy = true; status = nil; defer { busy = false }
        do {
            let value = try await Task.detached(priority: .utility) { try CoachDocumentReader.photo(bytes) }.value
            let source = try await store.importCoachDocument(value)
            status = "Salvato: \(source.document.name). Scegli le pagine da leggere."
        } catch { status = error.localizedDescription }
    }
    @MainActor private func readSelected() async {
        guard !unavailable else { return }
        let selected = sources.filter { selections[$0.id] != nil }
        guard selected.count == selections.count, (1...6).contains(selected.count), instruction.utf16.count <= 4000 else {
            status = "Controlla le fonti e limita la richiesta a 4000 caratteri."; return
        }
        var numbers = [UUID: [Int]]()
        for source in selected {
            guard let parsed = CoachDocumentPageSelection.parse(selections[source.id] ?? "", pageCount: source.pageCount) else {
                status = "Controlla le pagine di \(source.document.name)."; return
            }
            numbers[source.id] = parsed
        }
        guard numbers.values.reduce(0, { $0 + $1.count }) <= 40 else { status = "Scegli al massimo 40 pagine complessive. Non ne ho saltate alcune."; return }
        let requested = instruction, ocr = forceOCR
        busy = true; packet = nil; status = nil; defer { busy = false }
        do {
            var pages = [CoachDocumentPage]()
            for source in selected {
                pages += try await store.coachDocumentPages(source.id, numbers: numbers[source.id] ?? [], forceOCR: ocr)
                guard pages.reduce(0, { $0 + $1.text.utf16.count }) <= 120_000 else { throw CoachDocumentReader.Failure.selectionTooLong }
            }
            let value = CoachDocumentPacket(createdAt: Date(), instruction: requested, sources: selected, pages: pages)
            guard value.isCurrent(in: sources) else { throw CoachDocumentStorage.Failure.changed }
            let proposals = try CoachDocumentLocalProposals.analyze(value)
            _ = try await store.saveCoachDocumentReading(value, review: proposals)
            packet = value
        } catch { status = error.localizedDescription }
    }
}
