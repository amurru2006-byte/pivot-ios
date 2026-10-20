import Foundation

struct SavingsGoal: Codable, Identifiable, Equatable {
    enum Category: String, Codable { case debt, travel, purchase, other }
    var id = UUID()
    var name: String
    var targetCents: Int
    var category: Category = .other
    var deadline: Date? = nil
    var archived: Bool = false
    // The editor asks for a day, not a time. A hidden time retained by the
    // DatePicker must not change whether that day's contribution is included.
    var deadlineEndExclusive: Date? {
        guard let deadline, deadline.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return PivotDate.calendar.date(byAdding: .day, value: 1,
            to: PivotDate.calendar.startOfDay(for: deadline))
    }
}

struct BudgetExpense: Codable, Identifiable, Equatable {
    var id = UUID()
    var amountCents: Int
    var date: Date
    var description: String
    var voided: Bool? = nil
    var revisions: [BudgetExpenseRevision]? = nil
}

struct BudgetExpenseRevision: Codable, Equatable {
    var amountCents: Int
    var date: Date
    var description: String
    var voided: Bool
    var editedAt: Date
}

struct SavingsAllocation: Codable, Identifiable, Equatable {
    var id = UUID()
    var goalID: UUID
    // Positive reserves funds; negative releases a reservation. Neither is an expense.
    var cents: Int
    var date: Date
}

struct SavingsBudget: Codable {
    // Capture BEFORE reclassifying opening income into historical receipts.
    // Annual totals may change afterwards; this is not a bank balance.
    var openingFundsCents: Int
    var goals: [SavingsGoal] = []
    var expenses: [BudgetExpense] = []
    var allocations: [SavingsAllocation] = []
}

enum SavingsBudgetError: LocalizedError {
    case invalidData, missingGoal, insufficientFunds, excessiveRelease, goalLimit, conflict, reservedGoal
    var errorDescription: String? {
        switch self {
        case .invalidData: return "Controlla nome e importi. Nessun movimento è stato applicato."
        case .missingGoal: return "Questo obiettivo non è più disponibile."
        case .insufficientFunds: return "Non ci sono fondi liberi sufficienti per questo accantonamento."
        case .excessiveRelease: return "Puoi rendere disponibili soltanto i fondi già riservati a questo obiettivo."
        case .goalLimit: return "L’accantonamento supera l’importo dell’obiettivo."
        case .conflict: return "Questo movimento è già stato registrato con dati diversi."
        case .reservedGoal: return "Rendi disponibili i fondi dell’obiettivo prima di archiviarlo."
        }
    }
}

struct SavingsBalance: Equatable {
    var receivedCents: Int
    var spentCents: Int
    var reservedCents: Int
    var cashCents: Int { receivedCents - spentCents }
    var freeCents: Int { max(0, cashCents - reservedCents) }
    var shortfallCents: Int { max(0, reservedCents - cashCents) }
}

enum SavingsAccounting {
    static let maximumMovementCents = 100_000_000
    private static let maximumTotalCents = 1_000_000_000_000

    private static func sum(_ values: [Int]) throws -> Int {
        var total = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow, (-maximumTotalCents...maximumTotalCents).contains(next) else { throw SavingsBudgetError.invalidData }
            total = next
        }
        return total
    }

    static func reserved(for goalID: UUID, in budget: SavingsBudget) throws -> Int {
        try sum(budget.allocations.filter { $0.goalID == goalID }.map(\.cents))
    }

    static func validate(_ budget: SavingsBudget) throws {
        guard (0...maximumTotalCents).contains(budget.openingFundsCents),
              Set(budget.goals.map(\.id)).count == budget.goals.count,
              Set(budget.expenses.map(\.id)).count == budget.expenses.count,
              Set(budget.allocations.map(\.id)).count == budget.allocations.count,
              budget.goals.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...maximumMovementCents).contains($0.targetCents) }),
              budget.expenses.allSatisfy({ (1...maximumMovementCents).contains($0.amountCents)
                  && ($0.revisions ?? []).allSatisfy { (1...maximumMovementCents).contains($0.amountCents) } }) else { throw SavingsBudgetError.invalidData }
        var reserved: [UUID: Int] = [:]
        for move in budget.allocations {
            guard (-maximumMovementCents...maximumMovementCents).contains(move.cents), move.cents != 0,
                  let goal = budget.goals.first(where: { $0.id == move.goalID }) else { throw SavingsBudgetError.invalidData }
            let value = try sum([reserved[goal.id] ?? 0, move.cents])
            guard value >= 0 else { throw SavingsBudgetError.invalidData }
            reserved[goal.id] = value
        }
        guard budget.goals.allSatisfy({ reserved[$0.id, default: 0] <= $0.targetCents && (!$0.archived || reserved[$0.id, default: 0] == 0) }) else { throw SavingsBudgetError.invalidData }
    }

    static func balance(_ budget: SavingsBudget, payments: [Payment]) throws -> SavingsBalance {
        try validate(budget)
        guard Set(payments.map(\.id)).count == payments.count, payments.allSatisfy({ $0.amountCents > 0 }) else { throw SavingsBudgetError.invalidData }
        let received = try sum([budget.openingFundsCents] + payments.filter { $0.excludedFromBudget != true }.map(\.amountCents))
        let spent = try sum(budget.expenses.filter { $0.voided != true }.map(\.amountCents))
        let reserved = try sum(budget.allocations.map(\.cents))
        return .init(receivedCents: received, spentCents: spent, reservedCents: reserved)
    }

    /// Explicit migration boundary; never recompute after a historical backfill.
    static func initialize(data: inout AppData) throws {
        guard data.savingsBudget == nil else { return }
        let sources = Array((data.ledger?.openingCents ?? [:]).values)
        guard sources.allSatisfy({ $0 >= 0 }) else { throw SavingsBudgetError.invalidData }
        let opening = try sum(sources)
        let budget = SavingsBudget(openingFundsCents: opening)
        _ = try balance(budget, payments: data.payments)
        data.savingsBudget = budget
    }

    static func addGoal(_ goal: SavingsGoal, data: inout AppData) throws {
        var next = data
        try initialize(data: &next)
        guard !next.savingsBudget!.goals.contains(where: { $0.id == goal.id }) else { throw SavingsBudgetError.conflict }
        var clean = goal
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.savingsBudget!.goals.append(clean)
        try validate(next.savingsBudget!)
        data = next
    }

    static func editGoal(_ expected: SavingsGoal, replacement: SavingsGoal, data: inout AppData) throws {
        guard var budget = data.savingsBudget, let index = budget.goals.firstIndex(where: { $0.id == expected.id }) else { throw SavingsBudgetError.missingGoal }
        guard budget.goals[index] == expected, replacement.id == expected.id, replacement.archived == expected.archived else { throw SavingsBudgetError.conflict }
        var clean = replacement; clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard try reserved(for: expected.id, in: budget) <= clean.targetCents else { throw SavingsBudgetError.goalLimit }
        budget.goals[index] = clean
        try validate(budget)
        data.savingsBudget = budget
    }

    static func reserve(_ cents: Int, goalID: UUID, operationID: UUID = UUID(), at date: Date = Date(), data: inout AppData) throws {
        guard (1...maximumMovementCents).contains(cents) else { throw SavingsBudgetError.invalidData }
        try allocation(cents, goalID: goalID, operationID: operationID, date: date, data: &data)
    }

    static func release(_ cents: Int, goalID: UUID, operationID: UUID = UUID(), at date: Date = Date(), data: inout AppData) throws {
        guard (1...maximumMovementCents).contains(cents) else { throw SavingsBudgetError.invalidData }
        try allocation(-cents, goalID: goalID, operationID: operationID, date: date, data: &data)
    }

    private static func allocation(_ cents: Int, goalID: UUID, operationID: UUID, date: Date, data: inout AppData) throws {
        guard var budget = data.savingsBudget else { throw SavingsBudgetError.missingGoal }
        if let existing = budget.allocations.first(where: { $0.id == operationID }) {
            guard existing.goalID == goalID, existing.cents == cents else { throw SavingsBudgetError.conflict }
            return // A repeated confirmation cannot reserve the money twice.
        }
        guard let goal = budget.goals.first(where: { $0.id == goalID && !$0.archived }) else { throw SavingsBudgetError.missingGoal }
        let held = try reserved(for: goalID, in: budget)
        if cents > 0 {
            guard try balance(budget, payments: data.payments).freeCents >= cents else { throw SavingsBudgetError.insufficientFunds }
            guard held + cents <= goal.targetCents else { throw SavingsBudgetError.goalLimit }
        } else {
            guard held + cents >= 0 else { throw SavingsBudgetError.excessiveRelease }
        }
        budget.allocations.append(.init(id: operationID, goalID: goalID, cents: cents, date: date))
        try validate(budget)
        data.savingsBudget = budget
    }

    static func expense(_ expense: BudgetExpense, data: inout AppData) throws {
        var next = data
        try initialize(data: &next)
        if let existing = next.savingsBudget!.expenses.first(where: { $0.id == expense.id }) {
            guard existing == expense else { throw SavingsBudgetError.conflict }
            return
        }
        // A real expense must be recorded even when it reveals a shortfall.
        // Reservations are retained and shown as underfunded, never silently erased.
        next.savingsBudget!.expenses.append(expense)
        _ = try balance(next.savingsBudget!, payments: next.payments)
        data = next
    }

    static func archive(goalID: UUID, data: inout AppData) throws {
        guard var budget = data.savingsBudget, let index = budget.goals.firstIndex(where: { $0.id == goalID }) else { throw SavingsBudgetError.missingGoal }
        guard try reserved(for: goalID, in: budget) == 0 else { throw SavingsBudgetError.reservedGoal }
        budget.goals[index].archived = true
        try validate(budget)
        data.savingsBudget = budget
    }

    static func correctExpense(_ expected: BudgetExpense, amountCents: Int, date: Date, description: String,
                               voided: Bool = false, now: Date = Date(), data: inout AppData) throws {
        guard var budget = data.savingsBudget, let index = budget.expenses.firstIndex(where: { $0.id == expected.id }),
              budget.expenses[index] == expected else { throw SavingsBudgetError.conflict }
        guard (1...maximumMovementCents).contains(amountCents) else { throw SavingsBudgetError.invalidData }
        var next = expected
        guard next.amountCents != amountCents || next.date != date || next.description != description || (next.voided == true) != voided else { return }
        next.revisions = (next.revisions ?? []) + [.init(amountCents: next.amountCents, date: next.date,
            description: next.description, voided: next.voided == true, editedAt: now)]
        next.amountCents = amountCents; next.date = date; next.description = description; next.voided = voided
        budget.expenses[index] = next
        _ = try balance(budget, payments: data.payments)
        data.savingsBudget = budget
    }
}
