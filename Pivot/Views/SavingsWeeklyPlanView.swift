import SwiftUI

/// A plan reserves only the funds managed by Pivot. It never initiates a
/// bank transfer or creates Calendar events. Confirmation concerns cash/spend
/// completeness only, not the completeness of the activity history.
struct SavingsWeeklyPlanView: View {
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var agenda: AgendaService
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    @State private var automatic = false
    @State private var notify = true
    @State private var percent = 100
    @State private var weekday = 1
    @State private var hour = 20
    @State private var minute = 0
    @State private var initialized = false
    @State private var loadedPlan: SavingsWeeklyPlan?
    @State private var submitting = false
    @State private var message: String?
    @State private var reviewNow = Date()
    @State private var receipts = false
    @State private var expenses = false
    @State private var approval: SavingsWeeklyReview?
    @State private var confirming = false
    @State private var deleting = false
    private var goal: SavingsGoal? { store.data.savingsBudget?.goals.first { $0.id == goalID && !$0.archived } }
    private var review: SavingsWeeklyReview? {
        guard let goal, let budget = store.data.savingsBudget else { return nil }
        return try? .make(goalID: goalID, data: store.data, now: reviewNow,
            periodEnd: SavingsWeeklyAutomation.reviewEnd(goal: goal, budget: budget, now: reviewNow))
    }
    private var history: [SavingsAllocation] {
        (store.data.savingsBudget?.allocations ?? []).filter { $0.goalID == goalID && $0.weeklyReview != nil }
            .sorted { $0.date > $1.date }
    }
    private let days = ["Domenica", "Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato"]
    var body: some View {
        Form {
            if let goal {
                Section {
                    Text(goal.name).font(.headline)
                    Toggle("Accantona automaticamente", isOn: $automatic).accessibilityIdentifier("weekly-automatic")
                    Text(automatic ? "Pivot registra la quota nel Salvadanaio solo con incassi e spese verificati. Nessun trasferimento bancario." :
                        "Controlli la quota e decidi tu se accantonarla. Nessun trasferimento bancario.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                    Stepper("Quota del margine: \(percent)%", value: $percent, in: 0...100, step: 10)
                        .accessibilityIdentifier("weekly-percent")
                } header: { Text("Come vuoi mettere da parte?") }
                Section {
                    Picker("Giorno", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text(days[$0 - 1]).tag($0) }
                    }
                    DatePicker("Ora", selection: Binding(get: {
                        PivotDate.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reviewNow) ?? reviewNow
                    }, set: {
                        hour = PivotDate.calendar.component(.hour, from: $0)
                        minute = PivotDate.calendar.component(.minute, from: $0)
                    }), displayedComponents: .hourAndMinute)
                    Toggle("Notifica da Pivot", isOn: $notify).accessibilityIdentifier("weekly-notify")
                    Text("Non aggiunge eventi al Calendario. Se Pivot è chiusa, il calcolo e l’eventuale accantonamento si completano al prossimo aggiornamento dell’app.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                    Button(goal.weeklyPlan == nil || goal.weeklyPlan?.activatedAt == nil ? "Attiva piano" : "Salva piano") {
                        Task { await save() }
                    }.disabled(submitting || store.locked || store.isRestoring).accessibilityIdentifier("weekly-save")
                    if let plan = goal.weeklyPlan, plan.activatedAt != nil, let next = plan.nextReview(after: reviewNow) {
                        Text("Prossima verifica: " + DisplayDate.label(next, format: "EEE d MMM HH:mm"))
                            .font(.caption).accessibilityIdentifier("weekly-next")
                    }
                } header: { Text("Promemoria settimanale") }
                if let value = review {
                    Section {
                        Text(DisplayDate.label(value.weekStart, format: "d MMM HH:mm") + " – " + DisplayDate.label(value.periodEnd, format: "d MMM HH:mm"))
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                        LabeledContent("Incassi ordinari", value: Money.display(value.receivedCents))
                        LabeledContent("Spese", value: Money.display(value.spentCents))
                        LabeledContent("Già accantonati nel periodo", value: Money.display(max(0, value.alreadyReservedCents)))
                        if let amount = value.proposedCents {
                            LabeledContent("Quota disponibile", value: Money.display(amount)).accessibilityIdentifier("weekly-quota")
                            Button("Metti da parte questa quota") { approval = value; confirming = true }
                                .disabled(amount <= 0 || submitting || store.locked || goal.weeklyPlan?.activatedAt == nil)
                                .accessibilityIdentifier("weekly-reserve")
                        }
                        ForEach(value.issues, id: \.rawValue) { Text(explanation($0)).font(.caption).foregroundStyle(PivotTheme.amber) }
                        DisclosureGroup("Verifica incassi e spese") {
                            Text("Confermi tutte le registrazioni dal " + DisplayDate.label(value.weekStart, format: "d MMM HH:mm") + " fino a oggi. Anche le spese aggregate vanno bene.")
                                .font(.caption)
                            Toggle("Tutti gli incassi sono registrati", isOn: $receipts).accessibilityIdentifier("weekly-receipts")
                            Toggle("Tutte le spese sono registrate", isOn: $expenses).accessibilityIdentifier("weekly-expenses")
                            Button("Conferma fino a oggi") { confirmCoverage(start: value.weekStart) }
                                .disabled(!receipts || !expenses || store.locked || submitting)
                                .accessibilityIdentifier("weekly-verify")
                        }.accessibilityIdentifier("weekly-verification")
                        NavigationLink("Rivedi la stima dell’obiettivo") { SavingsEvidenceForecastView(goalID: goalID) }
                    } header: { Text("La quota di questa verifica") }
                }
                if !history.isEmpty {
                    Section("Accantonamenti settimanali") {
                        ForEach(history.prefix(12)) { move in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(DisplayDate.label(move.date, format: "d MMM yyyy HH:mm"))
                                    Text(move.weeklyReview?.automatic == true ? "Automatico" : "Confermato da te").font(.caption).foregroundStyle(PivotTheme.muted)
                                }
                                Spacer(); Text(Money.display(move.cents))
                            }.accessibilityIdentifier("weekly-receipt-" + move.id.uuidString)
                        }
                        Text("Puoi liberare gli importi da Rendi disponibili, senza cancellare lo storico.").font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                }
                if goal.weeklyPlan != nil {
                    Section {
                        Button("Elimina piano", role: .destructive) { deleting = true }.accessibilityIdentifier("weekly-delete")
                    }
                }
            } else { Text("Obiettivo non disponibile. Lo storico non è stato modificato.") }
            if let message { Section { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("weekly-message") } }
        }.navigationTitle("Piano settimanale")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .onAppear {
                guard !initialized else { return }; initialized = true
                loadedPlan = goal?.weeklyPlan
                let plan = loadedPlan ?? .init()
                automatic = plan.mode == .automatic; notify = plan.notificationsEnabled ?? true
                percent = plan.reservePercent; weekday = plan.weekday; hour = plan.hour; minute = plan.minute
                reviewNow = Date()
            }
            .onChange(of: store.data.updatedAt) { _, _ in reviewNow = Date() }
            .alert("Accantonare questa quota?", isPresented: $confirming) {
                Button("Annulla", role: .cancel) { approval = nil }
                Button("Conferma") { Task { await reserve() } }.accessibilityIdentifier("weekly-reserve-confirm")
            } message: { Text("Solo nel Salvadanaio di Pivot: " + Money.display(approval?.proposedCents ?? 0) + ". Nessun trasferimento bancario.") }
            .alert("Eliminare il piano?", isPresented: $deleting) {
                Button("Annulla", role: .cancel) {}
                Button("Elimina piano", role: .destructive) { Task { await remove() } }.accessibilityIdentifier("weekly-delete-confirm")
            } message: { Text("Rimuove il promemoria e gli accantonamenti automatici. Obiettivo, denaro già riservato e storico restano intatti.") }
    }
    private func explanation(_ issue: SavingsWeeklyReview.Issue) -> String {
        switch issue {
        case .verifyRecentData: "Verifica incassi e spese fino a oggi prima di usare la quota."
        case .receiptsNotConfirmed: "Conferma di avere registrato tutti gli incassi del periodo."
        case .expensesNotConfirmed: "Conferma di avere registrato tutte le spese del periodo."
        case .unknownReceiptDates: "Alcuni incassi hanno date da verificare: controlla il registro."
        case .underfunded: "Ci sono fondi mancanti: sistema il registro prima di accantonare."
        }
    }
    @MainActor private func save() async {
        guard !submitting, let goal, goal.weeklyPlan == loadedPlan else { message = "Il piano è cambiato: chiudi e riaprilo prima di salvare."; return }
        submitting = true; defer { submitting = false }
        let now = Date()
        var plan = SavingsWeeklyPlan(weekday: weekday, hour: hour, minute: minute, reservePercent: percent,
            mode: automatic ? .automatic : .manual, activatedAt: loadedPlan?.activatedAt ?? now, notificationsEnabled: notify)
        if loadedPlan?.weekday != weekday || loadedPlan?.hour != hour || loadedPlan?.minute != minute
            || (automatic && loadedPlan?.mode != .automatic) { plan.activatedAt = now }
        guard plan.isValid, let index = store.data.savingsBudget?.goals.firstIndex(where: { $0.id == goalID }) else { return }
        guard store.change({ $0.savingsBudget?.goals[index].weeklyPlan = plan }), await store.flushPendingWrites() else {
            message = "Salvataggio del piano non confermato. Riprova prima di chiudere."; return
        }
        loadedPlan = plan
        if !notify { await NotificationService.clearWeeklyReminders(goalID: goalID) }
        if notify { await notifications.requestAccess() }
        await notifications.schedule(events: agenda.planned, data: store.data)
        message = notify ? "Piano salvato. " + notifications.status : "Piano salvato, senza notifiche."
    }
    @MainActor private func confirmCoverage(start: Date) {
        let now = Date(), old = store.data.savingsCashCoverage
        // Preserve an earlier fully confirmed range. Otherwise confirm only
        // this displayed range, never unknown earlier weeks or activity data.
        let preserves = old?.isValid == true && old?.receiptsConfirmed == true && old?.expensesConfirmed == true && old!.from <= start
        let coverage = IncomeObservationCoverage(from: preserves ? old!.from : start, through: now,
            activitiesConfirmed: preserves ? old!.activitiesConfirmed : false, expensesConfirmed: true, receiptsConfirmed: true)
        guard coverage.isValid else { return }
        if store.change({ $0.savingsCashCoverage = coverage }) { reviewNow = now; message = "Registrazioni verificate. La quota è stata ricalcolata." }
    }
    @MainActor private func reserve() async {
        guard !submitting, let approval else { return }
        submitting = true; defer { submitting = false; self.approval = nil }
        do {
            var next = store.data
            let applied = try SavingsWeeklyAutomation.apply(goalID: goalID, expected: approval, automatic: false, now: Date(), data: &next)
            guard applied else { message = "Questa quota è già registrata o non c’è un importo da accantonare."; return }
            guard store.change({ $0 = next }), await store.flushPendingWrites() else { message = "Salvataggio non confermato: controlla lo storico prima di riprovare."; return }
            message = "Quota accantonata nel Salvadanaio. Nessun trasferimento bancario."
        } catch { message = "I dati sono cambiati: ricontrolla la quota prima di confermarla. " + error.localizedDescription }
    }
    @MainActor private func remove() async {
        guard !submitting, let index = store.data.savingsBudget?.goals.firstIndex(where: { $0.id == goalID }),
              goal?.weeklyPlan == loadedPlan else { message = "Il piano è cambiato: riaprilo prima di eliminarlo."; return }
        submitting = true; defer { submitting = false }
        guard store.change({ $0.savingsBudget?.goals[index].weeklyPlan = nil }), await store.flushPendingWrites() else {
            message = "Rimozione non confermata. Controlla il piano prima di riprovare."; return
        }
        await NotificationService.clearWeeklyReminders(goalID: goalID)
        await notifications.schedule(events: agenda.planned, data: store.data)
        dismiss()
    }
}
