import SwiftUI

private func savingsPreview(_ data: AppData) -> SavingsBudget? {
    var copy = data
    try? SavingsAccounting.initialize(data: &copy)
    return copy.savingsBudget
}

private enum SavingsMovementKind: String { case reserve, release, expense }
private enum SavingsRoute: Identifiable {
    case goal(SavingsGoal?), movement(SavingsMovementKind, UUID?), expense(BudgetExpense), forecast(UUID)
    var id: String {
        switch self {
        case .goal(let goal): return "goal-" + (goal?.id.uuidString ?? "new")
        case .movement(let kind, let id): return kind.rawValue + (id?.uuidString ?? "new")
        case .expense(let expense): return "expense-" + expense.id.uuidString
        case .forecast(let id): return "forecast-" + id.uuidString
        }
    }
}

struct SavingsPanel: View {
    @EnvironmentObject private var store: PivotStore
    var cardHeight: CGFloat = 300
    @State private var selectedGoalID: UUID?
    @State private var route: SavingsRoute?
    @State private var message: String?
    private var budget: SavingsBudget? { savingsPreview(store.data) }
    private var balance: SavingsBalance? { budget.flatMap { try? SavingsAccounting.balance($0, payments: store.data.payments) } }
    private var goals: [SavingsGoal] { budget?.goals.filter { !$0.archived } ?? [] }
    private var goal: SavingsGoal? { goals.first { $0.id == selectedGoalID } ?? goals.first }
    private var held: Int { guard let goal, let budget else { return 0 }; return (try? SavingsAccounting.reserved(for: goal.id, in: budget)) ?? 0 }
    private let orange = Color(pivotHex: "FFB56B")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            card
            if let balance {
                if balance.shortfallCents > 0 {
                    Label("Fondi mancanti: \(Money.display(balance.shortfallCents))", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("savings-shortfall")
                }
                if let goal {
                    Button { route = .forecast(goal.id) } label: { Label("Simula il tuo obiettivo", systemImage: "sparkles") }
                        .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("savings-forecast")
                    HStack {
                        Button("Metti da parte") { route = .movement(.reserve, goal.id) }
                            .buttonStyle(PivotPrimaryButton()).disabled(store.locked || balance.freeCents <= 0 || held >= goal.targetCents)
                            .accessibilityIdentifier("savings-reserve")
                        Button("Rendi disponibili") { route = .movement(.release, goal.id) }
                            .buttonStyle(PivotSecondaryButton()).disabled(store.locked || held <= 0)
                            .accessibilityIdentifier("savings-release")
                    }
                }
                Button { route = .movement(.expense, nil) } label: { Label("Registra spesa", systemImage: "minus.circle") }
                    .buttonStyle(PivotSecondaryButton()).disabled(store.locked).accessibilityIdentifier("savings-expense")
            }
            if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.amber) }
            if let expenses = budget?.expenses, !expenses.isEmpty {
                DisclosureGroup("Spese") {
                    ForEach(expenses.sorted { $0.date > $1.date }) { expense in
                        Button { route = .expense(expense) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(expense.description.isEmpty ? "Spesa" : expense.description).strikethrough(expense.voided == true)
                                    Text(DisplayDate.label(expense.date, format: "d MMM yyyy") + (expense.voided == true ? " · annullata" : ""))
                                        .font(.caption).foregroundStyle(PivotTheme.muted)
                                }
                                Spacer(); Text(Money.display(expense.amountCents)).strikethrough(expense.voided == true)
                            }.font(.subheadline).padding(.vertical, 6)
                        }.buttonStyle(.plain).accessibilityIdentifier("savings-expense-" + expense.id.uuidString)
                    }
                }.font(.subheadline).accessibilityIdentifier("savings-history")
            }
        }
        .sheet(item: $route) { item in
            switch item {
            case .goal(let existing): SavingsGoalForm(existing: existing) { selectedGoalID = $0 }
            case .movement(let kind, let goalID): SavingsMovementForm(kind: kind, goalID: goalID)
            case .expense(let expense): SavingsMovementForm(kind: .expense, goalID: nil, existingExpense: expense)
            case .forecast(let id): SavingsForecastView(goalID: id)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Salvadanaio", systemImage: "eurosign.circle.fill").font(.subheadline)
                Spacer()
                if let goal {
                    Menu {
                        if goals.count > 1 {
                            ForEach(goals) { item in Button(item.name) { selectedGoalID = item.id } }
                            Divider()
                        }
                        Button("Modifica obiettivo") { route = .goal(goal) }
                        Button("Nuovo obiettivo") { route = .goal(nil) }
                        Button("Archivia obiettivo") { archive(goal) }.disabled(held > 0)
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Gestisci obiettivo").accessibilityIdentifier("savings-goal-menu")
                }
            }.foregroundStyle(orange)
            if let balance {
                if let goal {
                    Text(Money.display(held)).foregroundStyle(orange)
                        .font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityIdentifier("savings-reserved-total")
                    Text("Obiettivo \(Money.display(goal.targetCents))").font(.subheadline).foregroundStyle(PivotTheme.muted)
                    ProgressView(value: Double(held), total: Double(goal.targetCents)).tint(orange)
                    Text(goal.name).font(.subheadline.weight(.semibold))
                    HStack {
                        if let deadline = goal.deadline { Text(DisplayDate.label(deadline, format: "d MMM yyyy")) }
                        Spacer()
                        Text("Liberi \(Money.display(balance.freeCents))").accessibilityIdentifier("savings-free-total")
                    }.font(.caption).foregroundStyle(PivotTheme.muted)
                } else {
                    Spacer(minLength: 8)
                    Button { route = .goal(nil) } label: {
                        Image(systemName: "plus").font(.system(size: 28, weight: .medium)).foregroundStyle(orange)
                            .frame(width: 66, height: 66).background(orange.opacity(0.12), in: Circle())
                            .overlay(Circle().strokeBorder(orange.opacity(0.45)))
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).disabled(store.locked).accessibilityLabel("Crea obiettivo")
                        .accessibilityIdentifier("savings-create-goal")
                    Spacer(minLength: 8)
                    Text("Liberi \(Money.display(balance.freeCents))").font(.caption).foregroundStyle(PivotTheme.muted)
                        .accessibilityIdentifier("savings-free-total")
                }
            } else {
                Text("Fondi non disponibili: controlla il registro prima di accantonare.").font(.subheadline)
            }
        }.padding(24).frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .topLeading)
            .background(LinearGradient(colors: [Color(pivotHex: "563A29"), Color(pivotHex: "302D3A"), PivotTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(orange.opacity(0.22)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("savings-summary")
    }

    private func archive(_ goal: SavingsGoal) {
        do {
            var next = store.data
            try SavingsAccounting.archive(goalID: goal.id, data: &next)
            if !store.change({ $0 = next }) { message = store.error }
        } catch { message = error.localizedDescription }
    }
}

private struct SavingsGoalForm: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    var existing: SavingsGoal?
    var onSaved: (UUID) -> Void
    @State private var name = ""
    @State private var target = ""
    @State private var category: SavingsGoal.Category = .other
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var message: String?
    @State private var initialized = false
    @State private var newID = UUID()
    @State private var submitting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Obiettivo") {
                    TextField("Nome", text: $name).accessibilityIdentifier("savings-goal-name")
                    TextField("Importo in euro", text: $target).keyboardType(.decimalPad).accessibilityIdentifier("savings-goal-target")
                    Picker("Categoria", selection: $category) {
                        Text("Debito").tag(SavingsGoal.Category.debt)
                        Text("Viaggio").tag(SavingsGoal.Category.travel)
                        Text("Acquisto").tag(SavingsGoal.Category.purchase)
                        Text("Altro").tag(SavingsGoal.Category.other)
                    }
                    Toggle("Scadenza", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Entro il", selection: $deadline, displayedComponents: .date) }
                }
                if let message { Text(message).foregroundStyle(PivotTheme.amber) }
                Button("Salva obiettivo") { save() }.disabled(store.locked || submitting)
                    .accessibilityIdentifier("savings-goal-save")
            }.navigationTitle(existing == nil ? "Nuovo obiettivo" : "Modifica obiettivo")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                }
                .pivotKeyboardToolbar()
                .onAppear {
                    guard !initialized else { return }; initialized = true
                    if let existing {
                        name = existing.name; target = String(Double(existing.targetCents) / 100)
                        category = existing.category; hasDeadline = existing.deadline != nil; deadline = existing.deadline ?? Date()
                    }
                }
        }
    }
    private func save() {
        guard !submitting else { return }
        submitting = true; defer { submitting = false }
        guard let cents = Money.cents(from: target) else { message = "Inserisci l’importo dell’obiettivo."; return }
        let goal = SavingsGoal(id: existing?.id ?? newID, name: name, targetCents: cents, category: category,
                               deadline: hasDeadline ? deadline : nil, archived: existing?.archived ?? false)
        do {
            var next = store.data
            if let existing { try SavingsAccounting.editGoal(existing, replacement: goal, data: &next) }
            else { try SavingsAccounting.addGoal(goal, data: &next) }
            if store.change({ $0 = next }) { onSaved(goal.id); dismiss() } else { message = store.error }
        } catch { message = error.localizedDescription }
    }
}

private struct SavingsMovementForm: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    var kind: SavingsMovementKind
    var goalID: UUID?
    var existingExpense: BudgetExpense? = nil
    @State private var amount = ""
    @State private var description = ""
    @State private var date = Date()
    @State private var message: String?
    @State private var initialized = false
    @State private var operationID = UUID()
    @State private var submitting = false
    private var title: String { switch kind { case .reserve: "Metti da parte"; case .release: "Rendi disponibili"; case .expense: existingExpense == nil ? "Registra spesa" : "Modifica spesa" } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Importo in euro", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("savings-movement-amount")
                    if kind == .expense {
                        TextField("Descrizione", text: $description, axis: .vertical).accessibilityIdentifier("savings-expense-description")
                        DatePicker("Data", selection: $date, displayedComponents: .date)
                    }
                    if let budget = savingsPreview(store.data), let balance = try? SavingsAccounting.balance(budget, payments: store.data.payments) {
                        Text("Liberi \(Money.display(balance.freeCents))").font(.subheadline)
                        if kind == .expense, let cents = Money.cents(from: amount), cents > balance.freeCents {
                            Text("Questa spesa può rendere insufficienti i fondi riservati. Le quote degli obiettivi non verranno ridotte automaticamente.")
                                .font(.caption).foregroundStyle(PivotTheme.amber)
                        }
                    }
                }
                if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("savings-movement-error") }
                Button("Conferma") { save() }.disabled(store.locked || submitting)
                    .accessibilityIdentifier("savings-movement-save")
                if let expense = existingExpense {
                    Button(expense.voided == true ? "Ripristina spesa" : "Annulla spesa", role: expense.voided == true ? nil : .destructive) {
                        save(voided: expense.voided != true)
                    }.disabled(store.locked || submitting)
                    if let edits = expense.revisions, !edits.isEmpty {
                        DisclosureGroup("Correzioni") {
                            ForEach(Array(edits.enumerated()), id: \.offset) { _, edit in
                                Text("\(DisplayDate.label(edit.editedAt, format: "d MMM HH:mm")) · \(Money.display(edit.amountCents))\(edit.voided ? " · annullata" : "")").font(.caption)
                            }
                        }
                    }
                }
            }.navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                }
                .pivotKeyboardToolbar()
                .onAppear {
                    guard !initialized else { return }; initialized = true
                    if let expense = existingExpense { amount = String(Double(expense.amountCents) / 100); description = expense.description; date = expense.date }
                }
        }
    }
    private func save(voided: Bool? = nil) {
        guard !submitting, let cents = Money.cents(from: amount), cents > 0 else { message = "Inserisci un importo maggiore di zero."; return }
        submitting = true; defer { submitting = false }
        do {
            var next = store.data
            switch kind {
            case .reserve:
                guard let goalID else { throw SavingsBudgetError.missingGoal }
                try SavingsAccounting.reserve(cents, goalID: goalID, operationID: operationID, data: &next)
            case .release:
                guard let goalID else { throw SavingsBudgetError.missingGoal }
                try SavingsAccounting.release(cents, goalID: goalID, operationID: operationID, data: &next)
            case .expense:
                if let expense = existingExpense {
                    try SavingsAccounting.correctExpense(expense, amountCents: cents, date: date, description: description,
                                                         voided: voided ?? (expense.voided == true), data: &next)
                } else {
                    try SavingsAccounting.expense(.init(id: operationID, amountCents: cents, date: date, description: description), data: &next)
                }
            }
            if store.change({ $0 = next }) { dismiss() } else { message = store.error }
        } catch { message = error.localizedDescription }
    }
}
