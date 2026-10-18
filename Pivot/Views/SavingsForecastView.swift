import SwiftUI
import UIKit

struct SavingsForecastView: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    @State private var upfront = "0"
    @State private var weekly = "0"
    private var goal: SavingsGoal? { store.data.savingsBudget?.goals.first { $0.id == goalID && !$0.archived } }
    private var forecast: SavingsGoalForecast? {
        guard let initial = Money.cents(from: upfront), let cadence = Money.cents(from: weekly) else { return nil }
        return .make(goalID: goalID, data: store.data, upfrontCents: initial, weeklyCents: cadence, now: Date())
    }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Quando arrivo all’obiettivo?", subtitle: goal?.name ?? "Obiettivo non disponibile")
                PivotCard {
                    Text("Simulazione, senza spostare denaro").font(.headline)
                    TextField("Da destinare ora (€)", text: $upfront).keyboardType(.decimalPad).accessibilityIdentifier("forecast-upfront")
                    TextField("Da mettere da parte ogni settimana (€)", text: $weekly).keyboardType(.decimalPad).accessibilityIdentifier("forecast-weekly")
                    Text("Scegli tu un ritmo sostenibile: lezioni previste e somme da incassare non sono fondi già disponibili.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                if let value = forecast {
                    PivotCard(tint: PivotTheme.amber) {
                        Text("Già accantonati \(Money.display(value.reservedCents))").font(.subheadline)
                        Text("Fondi liberi \(Money.display(value.freeCents))").font(.subheadline)
                        Text("Dopo l’ipotesi iniziale mancano \(Money.display(value.remainingCents))").font(.headline)
                            .accessibilityIdentifier("forecast-remaining")
                        if value.remainingCents == 0 {
                            Text("Con questa ipotesi raggiungeresti l’obiettivo ora.")
                        } else if let weeks = value.weeksNeeded, let date = value.completionDate {
                            Text("\(weeks) settimane · \(DisplayDate.label(date, format: "d MMM yyyy"))")
                                .accessibilityIdentifier("forecast-completion")
                        } else if value.weeklyCents == 0 {
                            Text("Indica una quota settimanale per vedere una data possibile.")
                        } else { Text("Il ritmo scelto porta oltre l’orizzonte della simulazione: non mostro una data utile.") }
                        if let deadline = goal?.deadline {
                            Text("Scadenza \(DisplayDate.label(deadline, format: "d MMM yyyy"))").font(.subheadline)
                            if value.deadlineMissed { Text("La scadenza è passata: puoi rivalutare l’obiettivo.").foregroundStyle(PivotTheme.amber) }
                            else if let required = value.requiredWeeklyCents, value.remainingCents > 0 {
                                Text("Servirebbero \(Money.display(required)) per ciascuna delle \(value.contributionsBeforeDeadline ?? 0) settimane intere rimaste.")
                            } else if value.remainingCents > 0 {
                                Text("Prima della scadenza non resta una settimana intera per il primo versamento ipotizzato.")
                            }
                        }
                        Text("Ipotesi: prima quota fra una settimana, poi ogni settimana, senza nuove spese o cambi d’incasso. Nessun movimento è stato registrato.")
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                } else {
                    Text("Controlla gli importi: la quota iniziale non può superare i fondi liberi o ciò che manca all’obiettivo. Se ci sono fondi mancanti, sistema prima il registro.")
                        .font(.subheadline).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("forecast-error")
                }
            }.navigationTitle("Scenario Salvadanaio")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Fine") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
                }
        }
    }
}
