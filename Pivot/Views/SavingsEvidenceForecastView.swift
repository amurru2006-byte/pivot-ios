import SwiftUI

/// Local calculation on immutable snapshots, not a prompt sent to the model.
/// Coverage is a user assertion; importing a few lessons never sets it for them.
struct SavingsEvidenceForecastView: View {
    @EnvironmentObject private var store: PivotStore
    let goalID: UUID
    @State private var from = PivotDate.calendar.date(byAdding: .weekOfYear, value: -26, to: StudentPayments.week(containing: Date()).start)!
    @State private var activities = false
    @State private var receipts = false
    @State private var expenses = false
    @State private var upfront = "0"
    @State private var percent = 100
    @State private var forecast: SavingsEvidenceForecast?
    @State private var problem: String?
    @State private var calculating = false
    private struct Calculation: Equatable {
        var revision: Date
        var upfront: String
        var percent: Int
        var locked: Bool
        var restoring: Bool
    }
    private var calculation: Calculation {
        .init(revision: store.data.updatedAt, upfront: upfront, percent: percent, locked: store.locked, restoring: store.isRestoring)
    }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Una stima sostenibile", subtitle: "Guadagni, incassi e spese restano distinti")
            PivotCard {
                Text("Quali dati sono completi?").font(.headline)
                DatePicker("Storico verificato dal", selection: $from, in: ...Date(), displayedComponents: .date)
                    .accessibilityIdentifier("evidence-from")
                Toggle("Ho registrato tutte le attività svolte", isOn: $activities).accessibilityIdentifier("evidence-activities")
                Toggle("Ho registrato tutti i pagamenti ricevuti", isOn: $receipts).accessibilityIdentifier("evidence-receipts")
                Toggle("Ho registrato tutte le spese da questi fondi", isOn: $expenses).accessibilityIdentifier("evidence-expenses")
                Text("Solo il denaro gestito in Pivot. Le spese possono essere anche aggregate. Importare alcune lezioni non rende completo il periodo.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                Button("Conferma dati fino a oggi") {
                    let coverage = IncomeObservationCoverage(from: from, through: Date(), activitiesConfirmed: activities,
                        expensesConfirmed: expenses, receiptsConfirmed: receipts)
                    guard coverage.isValid else { problem = "Scegli un inizio precedente a oggi."; return }
                    _ = store.change { $0.incomeObservationCoverage = coverage }
                }.buttonStyle(PivotPrimaryButton()).disabled(!activities || store.locked || store.isRestoring)
                    .accessibilityIdentifier("evidence-confirm")
                if let coverage = store.data.incomeObservationCoverage {
                    Text("Verificato fino al \(DisplayDate.label(coverage.through, format: "d MMM yyyy"))")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }
            PivotCard {
                Text("La tua scelta di risparmio").font(.headline)
                TextField("Fondi liberi da destinare ora (€)", text: $upfront).keyboardType(.decimalPad)
                    .accessibilityIdentifier("evidence-upfront")
                Stepper("Quota del margine da destinare: \(percent)%", value: $percent, in: 0...100, step: 10)
                    .accessibilityIdentifier("evidence-percent")
                Text("È un’ipotesi, non un versamento. Gli altri obiettivi mantengono i loro fondi.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
            if calculating { ProgressView("Aggiorno la stima…") }
            if let problem { Text(problem).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("evidence-error") }
            if let value = forecast {
                earnings(value)
                saving(value)
            }
        }.navigationTitle("Stima dai guadagni")
            .onAppear {
                if let coverage = store.data.incomeObservationCoverage {
                    from = coverage.from; activities = coverage.activitiesConfirmed
                    receipts = coverage.receiptsConfirmed; expenses = coverage.expensesConfirmed
                }
            }
            .task(id: calculation) { await calculate() }
    }
    private func average(_ values: [Int]) -> Int { values.isEmpty ? 0 : values.reduce(0, +) / values.count }
    private func earnings(_ value: SavingsEvidenceForecast) -> some View {
        PivotCard(tint: PivotTheme.accent) {
            Text("Lavoro ordinario previsto").font(.headline)
            Text("\(Money.display(average(value.income.weeks.dropFirst().prefix(4).map(\.earnedCents)))) a settimana")
                .font(.title2.bold()).accessibilityIdentifier("evidence-earned-weekly")
            Text("Media delle prossime quattro settimane intere. Regali, altre entrate straordinarie e contatti inattivi non alzano questa stima.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            Text("\(value.income.observations) settimane osservate · \(value.income.backtestCount) verifiche sul passato")
                .font(.caption)
            if let error = value.income.meanAbsoluteErrorCents {
                Text("Scarto medio nelle verifiche: \(Money.display(error)) a settimana").font(.caption)
            }
            Text("Il modello confronta livello recente, trend e, solo con almeno due anni completi, stagionalità personale. Non è una ricerca del mercato esterno.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
        }
    }
    @ViewBuilder private func saving(_ value: SavingsEvidenceForecast) -> some View {
        PivotCard(tint: PivotTheme.amber) {
            Text("Quanto potresti accantonare").font(.headline)
            ForEach(value.limitations, id: \.rawValue) { limitation in
                Text(explanation(limitation)).font(.subheadline).accessibilityIdentifier("evidence-limit-" + limitation.rawValue)
            }
            if !value.weeks.isEmpty {
                Text("\(Money.display(max(0, average(value.weeks.prefix(4).map(\.savingCents))))) a settimana")
                    .font(.title2.bold()).accessibilityIdentifier("evidence-saving-weekly")
                Text("Quota \(value.reservePercent)% degli incassi ordinari previsti, dopo le spese previste. Non tutti i guadagni sono già incassati.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                if value.weeks.prefix(4).contains(where: { $0.savingCents < 0 }) {
                    Text("Alcune settimane prevedono spese superiori agli incassi: quel disavanzo riduce il margine successivo.")
                        .font(.caption).foregroundStyle(PivotTheme.amber)
                }
                Text("Mancano \(Money.display(value.remainingCents))").font(.headline)
                if let date = value.completionDate {
                    Text(value.remainingCents == 0 ? "Obiettivo già coperto con questa ipotesi." : "Stima centrale: " + DisplayDate.label(date, format: "d MMM yyyy"))
                        .accessibilityIdentifier("evidence-completion")
                } else {
                    Text("Non emerge una data attendibile entro le prossime 52 settimane.").accessibilityIdentifier("evidence-no-date")
                }
                if let fast = value.fasterScenarioDate, let slow = value.slowerScenarioDate, fast != slow {
                    Text("Scenari: \(DisplayDate.label(fast, format: "d MMM yyyy")) – \(DisplayDate.label(slow, format: "d MMM yyyy"))")
                        .font(.subheadline)
                }
                if let deadline = value.deadline, let amount = value.projectedBeforeDeadlineCents {
                    Text("Entro il \(DisplayDate.label(deadline, format: "d MMM yyyy")): circa \(Money.display(amount)) su \(Money.display(value.remainingCents)) ancora necessari.")
                        .font(.subheadline)
                }
                Text("Si parte dalla prossima settimana intera, senza ricontare gli incassi di questa settimana. Le date seguono il ritmo osservato, non il contrario. Gli scenari non sono probabilità garantite.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
            Text("Calcolo locale, aggiornato quando cambiano i dati. Nessun saldo, pagamento o accantonamento viene modificato.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
        }
    }
    private func explanation(_ value: SavingsEvidenceForecast.Limitation) -> String {
        switch value {
        case .receiptsNotConfirmed: return "Conferma la completezza dei pagamenti per stimare il risparmio."
        case .unknownReceiptDates: return "Alcuni pagamenti non hanno una data verificata: la data della lezione assunta durante il recupero non dimostra quando hai incassato."
        case .expensesNotConfirmed: return "Le spese non sono confermate complete: non le considero pari a zero."
        case .provisional: return "Storico ancora breve: stima provvisoria, senza una data affidabile."
        }
    }
    @MainActor private func calculate() async {
        let key = calculation, data = store.data, now = Date(), selectedGoal = goalID
        forecast = nil; problem = nil
        guard !key.locked, !key.restoring else { return }
        guard let initial = Money.cents(from: upfront) else { problem = "Controlla i fondi iniziali dell’ipotesi."; return }
        calculating = true
        let result = await Task.detached(priority: .userInitiated) { () -> Result<SavingsEvidenceForecast, Error> in
            Result {
                let input = try OrdinaryIncomePreparation.make(data: data, coverage: data.incomeObservationCoverage, now: now)
                return try SavingsEvidenceForecast.make(goalID: selectedGoal, data: data, observations: input,
                    upfrontCents: initial, reservePercent: key.percent, now: now)
            }
        }.value
        guard !Task.isCancelled, calculation == key else { return }
        calculating = false
        switch result {
        case .success(let value): forecast = value
        case .failure(let error):
            switch error as? IncomeProjectionError {
            case .coverageRequired: problem = "Conferma prima il periodo in cui tutte le attività sono registrate."
            case .insufficientWeeks: problem = "Servono almeno otto settimane intere di storico verificato."
            case .staleCoverage: problem = "È iniziata una nuova settimana: verifica le registrazioni recenti e conferma i dati fino a oggi."
            default: problem = "Controlla periodo, importi e fondi liberi. La quota iniziale non può usare denaro di altri obiettivi o superare ciò che manca."
            }
        }
    }
}
