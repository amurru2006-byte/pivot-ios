import SwiftUI

struct BackupPasswordView: View {
    private enum Field: Hashable { case password, confirmation }
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var confirmation = ""
    @State private var savedElsewhere = false
    @State private var confirming = false
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("Password del backup") {
                    if !confirming {
                    SecureField("Password · almeno 12 caratteri", text: $password)
                        .textContentType(.newPassword).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused, equals: .password).submitLabel(.next)
                        .frame(minHeight: 44)
                        .onSubmit { advance() }
                        .privacySensitive().accessibilityIdentifier("backup-password")
                    Button("Ripeti la password") { advance() }
                        .disabled(password.count < 12).accessibilityIdentifier("backup-password-next")
                    } else {
                    SecureField("Ripeti la password", text: $confirmation)
                        .textContentType(.newPassword).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused, equals: .confirmation).submitLabel(.done)
                        .frame(minHeight: 44)
                        .onSubmit { focused = nil }
                        .privacySensitive().accessibilityIdentifier("backup-password-confirmation")
                    Button("Modifica la prima password") { focused = nil; confirming = false; savedElsewhere = false }
                        .accessibilityIdentifier("backup-password-back")
                    }
                }
                Section {
                    Text("Conserva la password fuori da Pivot: serve su un nuovo telefono o dopo una reinstallazione. Se la perdi, quel backup non potrà essere recuperato.")
                    if confirming { Toggle("Ho conservato la password in un posto sicuro", isOn: $savedElsewhere)
                        .accessibilityIdentifier("backup-password-saved")
                    }
                    Text("L’iPhone conserva solo la chiave nel proprio portachiavi, senza sincronizzarla. Cambiare password protegge le nuove copie; quelle precedenti restano legate alla vecchia password.").font(.caption)
                }
                if confirming { Section {
                    Button(store.isConfiguringBackupPassword ? "Verifico la protezione…" : "Attiva backup cifrati") {
                        let pass = password, repeated = confirmation
                        task = Task {
                            if await store.configureBackupPassword(pass, confirmation: repeated), !Task.isCancelled {
                                password = ""; confirmation = ""; dismiss()
                            }
                        }
                    }.disabled(!savedElsewhere || password.isEmpty || password != confirmation || store.isConfiguringBackupPassword)
                        .accessibilityIdentifier("backup-password-save")
                    Text(store.backupStatus).font(.caption)
                } }
            }.navigationTitle("Proteggi il backup")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { cancel(); dismiss() } }
                }
                .pivotKeyboardToolbar { focused = nil }
                .onChange(of: scenePhase) { _, phase in if phase == .background { cancel(); dismiss() } }
                .onDisappear { cancel() }
        }
    }
    private func advance() {
        guard password.count >= 12 else { return }
        // Only one secure field is mounted at a time. Native focus/AutoFill
        // cannot be retained by the first field while entering confirmation.
        focused = nil; confirmation = ""; savedElsewhere = false; confirming = true
    }
    private func cancel() { task?.cancel(); task = nil; focused = nil; password = ""; confirmation = ""; savedElsewhere = false; confirming = false }
}
