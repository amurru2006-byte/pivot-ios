import SwiftUI

struct SignatureRenewalReminder: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pivot.signatureRenewal.confirmation") private var confirmationData = Data()
    @State private var notice: Notice?
    @State private var checkOnActivation = true

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .background {
                    checkOnActivation = true
                } else if phase == .active && checkOnActivation {
                    checkOnActivation = false
                    refresh()
                }
            }
            .fullScreenCover(item: $notice) { notice in
                SignatureRenewalPrompt(deadline: notice.deadline) {
                    self.notice = nil
                } didRenew: {
                    refresh(confirmedProfileExpiry: notice.profileExpiry)
                }
                .interactiveDismissDisabled()
            }
    }

    private func refresh(confirmedProfileExpiry: Date? = nil) {
        guard let profileExpiry = Self.installedProfileExpiry() else {
            notice = nil
            return
        }
        let now = Date()
        var confirmation = try? JSONDecoder().decode(SignatureRenewal.Confirmation.self, from: confirmationData)
        if let existing = confirmation, existing.profileExpiry != profileExpiry {
            confirmation = nil
            confirmationData = Data()
        }
        if confirmedProfileExpiry == profileExpiry {
            let updated = SignatureRenewal.Confirmation(profileExpiry: profileExpiry, confirmedAt: now)
            if let encoded = try? JSONEncoder().encode(updated) {
                confirmation = updated
                confirmationData = encoded
            }
        }
        let deadline = SignatureRenewal.deadline(profileExpiry: profileExpiry, confirmation: confirmation, now: now)
        notice = deadline.needsReminder(at: now) ? Notice(profileExpiry: profileExpiry, deadline: deadline) : nil
    }

    private static func installedProfileExpiry() -> Date? {
        let bundle = Bundle.main
        guard let bundleID = bundle.bundleIdentifier,
              let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let file = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: SignatureRenewal.profileByteLimit + 1) else { return nil }
        return SignatureRenewal.profileExpiry(in: data, bundleID: bundleID)
    }

    private struct Notice: Identifiable {
        let profileExpiry: Date
        let deadline: SignatureRenewal.Deadline

        var id: Date { deadline.date }
    }
}

private struct SignatureRenewalPrompt: View {
    let deadline: SignatureRenewal.Deadline
    let close: () -> Void
    let didRenew: () -> Void
    @State private var confirmingRenewal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rinnova Pivot in AltStore")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(deadline.estimated ? "Scadenza stimata dopo il rinnovo" : "Scadenza indicata dal profilo di Pivot")
                    .foregroundStyle(.secondary)
                Text(deadline.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text("Apri AltStore Classic, vai in My Apps e rinnova Pivot. Poi torna qui e premi Fatto se AltStore mostra che il rinnovo è riuscito.")
                Button("Fatto") { confirmingRenewal = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Chiudi per ora")
            }
            .padding(.horizontal, 12)
        }
        .alert("Hai appena rinnovato Pivot?", isPresented: $confirmingRenewal) {
            Button("Conferma rinnovo", action: didRenew)
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Conferma solo dopo aver visto il rinnovo riuscito in AltStore. Se il profilo di Pivot è rimasto uguale, il prossimo promemoria userà una stima di sette giorni da adesso.")
        }
    }
}
