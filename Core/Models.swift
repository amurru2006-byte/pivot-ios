import Foundation

enum EventKind: String, Codable, CaseIterable {
    // Keep `social` so existing backups remain readable.
    case routine, meal, study, workout, university, tutoring, work, social, partner, friends, exam, other
    var label: String {
        switch self {
        case .routine: return "Routine"
        case .meal: return "Pasto"
        case .study: return "Studio"
        case .workout: return "Palestra / cardio"
        case .university: return "Università"
        case .tutoring: return "Ripetizioni"
        case .work: return "Lavoro"
        case .social: return "Sociale"
        case .partner: return "Des"
        case .friends: return "Amici"
        case .exam: return "Esame"
        case .other: return "Altro"
        }
    }
    static func classify(title: String, calendar: String) -> EventKind {
        let t = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let c = calendar.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        // Some calendar providers discard URL metadata during synchronization.
        // A plain journey must not become a lesson or workout just by its calendar.
        if t.trimmingCharacters(in: .whitespacesAndNewlines) == "spostamento" { return .other }
        let calendarWords = c.components(separatedBy: CharacterSet.alphanumerics.inverted)
        // A dedicated calendar is authoritative; never infer a partner from "destinazione".
        if calendarWords.contains("amici") { return .friends }
        if calendarWords.contains("des") || calendarWords.contains("desiree") { return .partner }
        let titleWords = t.components(separatedBy: CharacterSet.alphanumerics.inverted)
        if calendarWords.contains("lavoro") {
            return titleWords.contains("lezione") || titleWords.contains("studente") || t.contains("ripetizion") ? .tutoring : .work
        }
        if t.contains("ripetizioni") || t.contains("lezione mamma") { return .tutoring }
        if t.contains("esame") || t.contains("compitino") { return .exam }
        if ["colazione", "pranzo", "merenda", "cena", "spuntino"].contains(where: t.contains) { return .meal }
        if t.contains("studio") || t.contains("ripasso") || t.contains("simulazione") { return .study }
        if ["palestra", "cardio", "camminata", "escursione", "tapis roulant", "treadmill"].contains(where: t.contains) || c.contains("palestra") { return .workout }
        if c.contains("unimi") || calendarWords.contains("uni") || t.contains("laboratorio") { return .university }
        if titleWords.contains("amici") { return .friends }
        if titleWords.contains("des") || titleWords.contains("desiree") { return .partner }
        if ["sveglia", "sonno", "preparo domani", "relax"].contains(where: t.contains) { return .routine }
        return .other
    }
}

enum EventFlexibility: String, Codable, CaseIterable {
    case fixed, movable, compressible, optional
    var label: String {
        switch self {
        case .fixed: return "Fisso"
        case .movable: return "Spostabile"
        case .compressible: return "Accorciabile, con conferma"
        case .optional: return "Rinunciabile, con conferma"
        }
    }
}

struct CalendarItem: Codable, Identifiable, Equatable {
    var id: String
    var eventIdentifier: String
    var externalIdentifier: String?
    var calendarIdentifier: String
    var calendarTitle: String
    var title: String
    var start: Date
    var end: Date
    var location: String
    var notes: String
    var colorHex: String
    var isAllDay: Bool
    var writable: Bool
    var kind: EventKind
    // Optional metadata keeps previous backups compatible.
    var sourceIdentifier: String? = nil
    var sourceTitle: String? = nil
    var calendarModifiedAt: Date? = nil
    var recurring: Bool? = nil
    var occurrenceAnchor: Date? = nil
    var calendarRGB: CalendarRGB? = nil
    var calendarCreatedAt: Date? = nil
    var durationMinutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
    func agendaStart(on day: Date) -> String {
        if isAllDay { return "Oggi" }
        return start < PivotDate.calendar.startOfDay(for: day) ? "In corso" : PivotDate.time(start)
    }
    func agendaEnd(on day: Date) -> String {
        if isAllDay { return "" }
        return PivotDate.calendar.isDate(end, inSameDayAs: day) ? PivotDate.time(end) : "→ \(PivotDate.time(end))"
    }
    func occurs(on day: Date) -> Bool {
        let from = PivotDate.calendar.startOfDay(for: day)
        let to = PivotDate.calendar.date(byAdding: .day, value: 1, to: from)!
        return start < to && end > from
    }
    var timeSummary: String {
        let calendar = PivotDate.calendar
        if isAllDay {
            let finalDay = end.addingTimeInterval(-1)
            if calendar.isDate(start, inSameDayAs: finalDay) { return "Tutto il giorno" }
            return "\(PivotDate.shortDate(start)) – \(PivotDate.shortDate(finalDay)) · tutto il giorno"
        }
        if !calendar.isDate(start, inSameDayAs: end) {
            return "\(PivotDate.shortDate(start)) \(PivotDate.time(start)) – \(PivotDate.shortDate(end)) \(PivotDate.time(end))"
        }
        return "\(PivotDate.time(start)) – \(PivotDate.time(end)) · \(durationMinutes) min"
    }
}

enum Completion: String, Codable, CaseIterable {
    case pending, running, completed, partial, skipped
    var label: String {
        switch self {
        case .pending: return "Da compilare"
        case .running: return "In corso"
        case .completed: return "Fatto"
        case .partial: return "Parziale"
        case .skipped: return "Saltato"
        }
    }
}

struct EventRecord: Codable, Identifiable {
    var id: String
    var snapshot: CalendarItem
    var status: Completion = .pending
    var actualStart: Date?
    var actualEnd: Date?
    var activeMinutes: Int = 0
    var reason: String = ""
    var notes: String = ""
    var hungerBefore: Int? = nil
    var hungerAfter: Int? = nil
    var energy: Int? = nil
    var fatigue: Int? = nil
    // A suggestion from the calendar, never a measured value. Manual edits persist.
    var timingFromCalendar: Bool? = nil
    // Explicit clock edits awaiting a Calendar confirmation. Health imports,
    // timers and autofill never set this user-intent marker.
    var calendarTimingNeedsConfirmation: Bool? = nil
    // Optional provenance: deleting a workout must not erase independent diary data.
    var trainingSessionID: UUID? = nil
    var followedMeal: Bool? = nil
    var reflection: ActivityReflection? = nil
    var study: StudySession? = nil
    var incomeID: UUID? = nil
    var tutoringAnswered: Bool? = nil
    var logistics: LessonLogistics? = nil
    var reminders: String? = nil
    var cardio: CardioRecord? = nil
    var health: HealthWorkoutSummary? = nil
    var healthSleep: SleepRecord? = nil
    var updatedAt: Date = Date()
}

struct ActivityReflection: Codable {
    var focus: String = ""
    var result: String = ""
    var nextStep: String = ""
}

struct EventRule: Codable {
    var flexibility: EventFlexibility
    var minimumMinutes: Int
    var travelBeforeMinutes: Int = 0
    var travelAfterMinutes: Int = 0
    var travelConfirmed: Bool = false
    var priority: EventPriority? = nil
    var kindOverride: EventKind? = nil
    var compressionApproved: Bool? = nil
    static func effective(for item: CalendarItem, data: AppData) -> EventRule {
        var rule = data.rules[item.id] ?? defaultRule(for: item)
        if let logistics = data.records[item.id]?.logistics,
           !logistics.isConfirmed(for: item) { rule.travelConfirmed = false }
        return rule
    }
    static func defaultRule(for item: CalendarItem) -> EventRule {
        let t = item.title.lowercased()
        switch item.kind {
        case .meal:
            let minimum = t.contains("colazione") ? 15 : (t.contains("merenda") || t.contains("spuntino") ? 10 : 30)
            return EventRule(flexibility: .compressible, minimumMinutes: minimum)
        case .study: return EventRule(flexibility: .compressible, minimumMinutes: 60)
        case .workout: return EventRule(flexibility: .movable, minimumMinutes: item.durationMinutes)
        default: return EventRule(flexibility: .fixed, minimumMinutes: item.durationMinutes)
        }
    }
}

struct DayCheckIn: Codable, Identifiable {
    var id: String
    var wakeTime: Date?
    var energyMorning: Int? = nil
    var energyEvening: Int? = nil
    var moodMorning: Int? = nil
    var moodEvening: Int? = nil
    var fatigueMorning: Int? = nil
    var fatigueEvening: Int? = nil
    var notes: String = ""
    // Optional so backups from 0.2 decode without this field.
    var universityAttendance: Bool? = nil
    var sleep: SleepRecord? = nil
    var healthWakeTime: Date? = nil
}

struct Client: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rateCents: Int
    var paymentCadence: PaymentCadence? = nil
    // Explicitly confirmed calendar names, never AI-inferred identities.
    var calendarAliases: [String]? = nil
    var activity: IncomeActivityKind? = nil
    var billing: IncomeBilling? = nil
    // Optional for backwards-compatible backups; never changes past receipts.
    var defaults: ClientDefaults? = nil
    var activityState: ClientActivityState? = nil
    var ordinaryForecastEnabled: Bool? = nil
    var activityKind: IncomeActivityKind { activity ?? .lesson }
    // Lessons default to ordinary work. Other work needs explicit opt-in;
    // a one-off job must not become a recurring salary. Gifts never qualify.
    var participatesInOrdinaryForecast: Bool {
        [.lesson, .work].contains(activityKind) && (ordinaryForecastEnabled ?? (activityKind == .lesson))
    }
    var billingMode: IncomeBilling { activityKind == .gift ? .fixed : billing ?? .hourly }
}

struct IncomeEntry: Codable, Identifiable {
    var id = UUID()
    var clientID: UUID
    var clientName: String
    var date: Date
    var minutes: Int
    var amountCents: Int
    var paidCents: Int = 0
    var notes: String = ""
    var calendarEventID: String? = nil
    var paymentTiming: PaymentTiming? = nil
    var promisedPaymentDate: Date? = nil
    var paymentDeferralAfter: Date? = nil
    var lastKnownPaymentDate: Date? = nil
    var historicalSource: HistoricalIncomeSource? = nil
    var activity: IncomeActivityKind? = nil
    var billing: IncomeBilling? = nil
    var activityKind: IncomeActivityKind { activity ?? .lesson }
    var hasDuration: Bool { activityKind == .lesson || (activityKind != .gift && (billing ?? .hourly) == .hourly) }
    var outstandingCents: Int { max(0, amountCents - paidCents) }
}

struct Payment: Codable, Identifiable {
    var id = UUID()
    var incomeID: UUID
    var clientName: String
    var date: Date?
    var amountCents: Int
    // Historical earnings can belong to annual reporting without being funds
    // still available today. Nil preserves all existing normal receipts.
    var excludedFromBudget: Bool? = nil
    // A confirmed year is not a fabricated payment day/month.
    var receivedYear: Int? = nil
    var year: Int? { date.map { PivotDate.calendar.component(.year, from: $0) } ?? receivedYear }
    func occurred(from start: Date, to end: Date) -> Bool { date.map { $0 >= start && $0 < end } ?? false }
}

struct PlanMove: Codable, Identifiable {
    var id = UUID()
    var source: CalendarItem
    var proposedStart: Date
    var proposedEnd: Date
    var healthDerived: Bool? = nil
    var syncedToCalendar: Bool = false
    var createdAt: Date = Date()
}

enum CoachRole: String, Codable, Equatable {
    case user, coach, system
}

struct CoachMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var dayKey: String
    var role: CoachRole
    var text: String
    var createdAt = Date()
    var healthDerived: Bool? = nil
    // Nil (including legacy/local messages) is NOT permission to retransmit.
    var onlineHistoryEligible: Bool? = nil
    // Local hand-off, never part of the provider's message schema.
    var recoveryRequest: CoachRecoveryRequest? = nil
}

struct CoachOption: Codable, Identifiable {
    var id = UUID()
    var title: String
    var explanation: String
    var consequences: String
    var moves: [PlanMove]
    var createdAt = Date()
}

struct PendingCalendarChange: Codable, Identifiable {
    var id = UUID()
    var move: PlanMove
    var optionTitle: String
    var createdAt = Date()
    var conflictMessage: String? = nil
}

struct CoachMemory: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    var expiresAt: Date? = nil
    // Explicit opt-in for this exact user-written memory. Legacy entries stay local.
    var onlineSharingAllowed: Bool? = nil
    var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 1500
            && (onlineSharingAllowed != true || text.utf16.count <= 240)
            && createdAt.timeIntervalSinceReferenceDate.isFinite
            && (expiresAt.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 > createdAt } ?? true)
    }
    func isActive(at now: Date) -> Bool {
        isValid && now.timeIntervalSinceReferenceDate.isFinite && createdAt <= now && (expiresAt.map { $0 > now } ?? true)
    }
}

struct CoachState: Codable {
    var messages: [CoachMessage] = []
    var options: [CoachOption] = []
    var pendingCalendarChanges: [PendingCalendarChange] = []
    var memories: [CoachMemory] = []
    var calendarDrafts: [CoachSavedCalendarDraft]? = nil
    var calendarBatches: [CoachCalendarBatch]? = nil
    var focusedCalendarDraftID: UUID? = nil
    var omitPreviousDraft: Bool? = nil
    var contextStartedAt: Date? = nil
}

struct Settings: Codable, Equatable {
    var excludedCalendarIDs: [String] = []
    var excludedCalendarTitles: [String] = []
    var excludeHolidays: Bool = true
    var morningDelayMinutes: Int = 30
    var quietStartHour: Int = 22
    var quietEndHour: Int = 8
    var repeatMissedNotifications: Bool = true
    var eveningHour: Int = 21
    var eveningMinute: Int = 45
    var studyPriorityFrom: Date? = nil
    var studyMustTakePriority: Bool = false
    // Optional additions decode old installations without replacing their settings.
    var healthEnabled: Bool? = nil
    var includeHealthInExports: Bool? = nil
    var includeCoachInReports: Bool? = nil
    var notificationPolicyVersion: Int? = nil
    var cardioReviewMinimumMinutes: Int? = nil
    var cardioReviewMinimumCalories: Int? = nil
    // -1 explicitly disables a target; absent energy defaults to the editable 7/10.
    var ratingTargets: [String: Int]? = nil
    var preferredNewEventCalendarID: String? = nil
    var calendarCreationAliases: [String: String]? = nil
    var preferredNewEventSourceID: String? = nil
    // Confirmed locally; neither account IDs nor these associations go online.
    var calendarTopicRoutes: [String: String]? = nil
    var recoveryPlanningPreferences: RecoveryPlanningPreferences? = nil
    var workoutRestAudio: WorkoutRestAudioSettings? = nil
}

struct AppData: Codable {
    var schemaVersion: Int = 1
    var installationID = UUID()
    var updatedAt: Date = Date()
    var records: [String: EventRecord] = [:]
    var rules: [String: EventRule] = [:]
    var checkIns: [String: DayCheckIn] = [:]
    var clients: [Client] = []
    var income: [IncomeEntry] = []
    var payments: [Payment] = []
    var moves: [PlanMove] = []
    var settings = Settings()
    var ledger: AnnualLedger? = nil
    // Embedded PDF bytes exist only in a complete backup, never in the live JSON.
    var studyPDFs: [String: Data]? = nil
    var training: TrainingLibrary? = nil
    var lessonDefaults: [String: LessonLogistics]? = nil
    var lessonPrompts: LessonPromptState? = nil
    // Optional so every existing backup remains readable without a migration.
    var coach: CoachState? = nil
    var decisions: [EventDecision]? = nil
    var contextAnswers: [ContextAnswer]? = nil
    var activityDrafts: [String: ActivityDraft]? = nil
    var workoutReviews: [WorkoutReview]? = nil
    var actualWorkoutDraft: ActualWorkoutDraft? = nil
    var strengthProfile: StrengthProfile? = nil
    var incomeEdits: [IncomeEdit]? = nil
    var savingsBudget: SavingsBudget? = nil
    var incomeObservationCoverage: IncomeObservationCoverage? = nil
    var calendarActionArchive: [ArchivedCalendarMutation]? = nil
    var calendarRestorations: [CalendarRestorationLink]? = nil
}

struct ActivityDraft: Codable {
    var record: EventRecord
    var rule: EventRule
    var studentName: String
    var clientID: UUID?
    var lessonAmount: String
    var receivedAmount: String
    var received: Bool
    var receiptDate: Date
    var paymentTiming: PaymentTiming? = nil
    var promisedPaymentDate: Date? = nil
    var rememberPaymentCadence: Bool? = nil
}

enum PivotDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = calendar.timeZone
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}

enum Money {
    static func cents(from text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), decimal >= 0,
              normalized.allSatisfy({ $0.isNumber || $0 == "." }), normalized.filter({ $0 == "." }).count <= 1 else { return nil }
        let value = decimal * 100
        var rounded = Decimal()
        var original = value
        NSDecimalRound(&rounded, &original, 0, .plain)
        guard rounded <= Decimal(100_000_000) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }
    static func lessonAmount(rateCents: Int, minutes: Int) -> Int {
        Int((Double(rateCents) * Double(minutes) / 60).rounded())
    }
    static func display(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "it_IT")
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "€ 0,00"
    }
}
