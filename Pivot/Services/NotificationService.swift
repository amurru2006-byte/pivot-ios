import UserNotifications
import Foundation
import Combine

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    struct Route: Identifiable {
        var id = UUID()
        var eventID: String?
        var destination: String
        var outcome: Completion?
        var clientID: String? = nil
        var sessionID: String? = nil
        var goalID: String? = nil
    }
    @Published var route: Route?
    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "done", title: "Fatto", options: [.foreground])
        let partial = UNNotificationAction(identifier: "partial", title: "Parziale", options: [.foreground])
        let deferAction = UNNotificationAction(identifier: "later", title: "Più tardi", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "event-result", actions: [done, partial, deferAction], intentIdentifiers: [], options: [])])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == "later" {
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
            return
        }
        let eventID = info["eventID"] as? String
        let destination = info["destination"] as? String ?? "today"
        let outcome: Completion? = response.actionIdentifier == "done" ? .completed : (response.actionIdentifier == "partial" ? .partial : nil)
        let clientID = info["clientID"] as? String
        let sessionID = info["sessionID"] as? String
        let goalID = info["goalID"] as? String
        await MainActor.run { self.route = Route(eventID: eventID, destination: destination, outcome: outcome, clientID: clientID, sessionID: sessionID, goalID: goalID) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list, .sound] }
    @Published private(set) var status = "Notifiche non configurate"
    private var generation = 0
    private var lastLessonPromptIDs: Set<String> = []
    private var synthetic: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--interaction-test")
        #else
        return false
        #endif
    }
    func requestAccess() async {
        if synthetic { status = "Collaudo sintetico · nessuna notifica reale"; return }
        do {
            let ok = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            status = ok ? "Notifiche autorizzate" : "Notifiche negate: abilita Pivot nelle impostazioni di iOS"
        } catch { status = error.localizedDescription }
    }
    static func clearWeeklyReminders(goalID: UUID? = nil) async {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test") { return }
        #endif
        let center = UNUserNotificationCenter.current()
        func owned(_ id: String) -> Bool { goalID.map { id == "savings-weekly-" + $0.uuidString } ?? id.hasPrefix("savings-weekly-") }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter(owned))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter(owned))
    }
    func schedule(events: [CalendarItem], data: AppData) async {
        if synthetic { status = "Collaudo sintetico · nessuna notifica reale"; return }
        generation += 1
        let token = generation
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard token == generation else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            status = "Notifiche non autorizzate"; return
        }
        let pending = await center.pendingNotificationRequests()
        guard token == generation else { return }
        let reserved = pending.filter { $0.identifier.hasPrefix("income-") || $0.identifier.hasPrefix("workout-rest-") || $0.identifier == "pivot-online-coach-retry" }.count
        let allWeekly = SavingsWeeklyNotification.make(data: data)
        let weekly = Array(allWeekly.prefix(max(0, 57 - reserved)))
        var weeklyWarning: String? = allWeekly.count > weekly.count ? "Alcuni promemoria Salvadanaio non entrano nella coda di iOS: riduci gli avvisi attivi." : nil
        let requests = await Task.detached(priority: .utility) {
            NotificationPlan.requestsFromPlanned(events: events, data: data, now: Date(), capacity: min(57, max(0, 60 - reserved - weekly.count)))
        }.value
        guard token == generation else { return }
        let wanted = Set(requests.map(\.id) + weekly.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !$0.identifier.hasPrefix("income-") && !$0.identifier.hasPrefix("workout-rest-") && !$0.identifier.hasPrefix("lesson-place-") && $0.identifier != "pivot-online-coach-retry" && !wanted.contains($0.identifier) }.map(\.identifier))
        let existing = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { _, newer in newer })
        var count = 0
        for reminder in weekly {
            guard token == generation, !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = "Il tuo piano di risparmio"
            content.body = "Apri Pivot per controllare la quota aggiornata e gli accantonamenti. Nessun trasferimento bancario."
            content.sound = .default
            content.userInfo = ["destination": "savings", "goalID": reminder.goalID.uuidString]
            var components = DateComponents()
            components.weekday = reminder.weekday; components.hour = reminder.hour; components.minute = reminder.minute
            components.second = 0; components.timeZone = PivotDate.calendar.timeZone
            if let old = existing[reminder.id], let trigger = old.trigger as? UNCalendarNotificationTrigger,
               trigger.repeats, trigger.dateComponents == components,
               old.content.title == content.title, old.content.body == content.body,
               old.content.userInfo["goalID"] as? String == reminder.goalID.uuidString { continue }
            do { try await center.add(.init(identifier: reminder.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))) }
            catch { weeklyWarning = "Promemoria Salvadanaio non confermato. Verifica le notifiche nelle Impostazioni." }
        }
        for request in requests {
            guard token == generation, !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.userInfo = ["eventID": request.eventID ?? "", "destination": request.destination, "clientID": request.clientID ?? ""]
            if request.id.hasPrefix("event-") { content.categoryIdentifier = "event-result" }
            if let old = existing[request.id], old.content.title == content.title, old.content.body == content.body,
               old.content.categoryIdentifier == content.categoryIdentifier,
               old.content.userInfo["eventID"] as? String == content.userInfo["eventID"] as? String,
               old.content.userInfo["destination"] as? String == content.userInfo["destination"] as? String,
               old.content.userInfo["clientID"] as? String == content.userInfo["clientID"] as? String,
               let date = (old.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? (old.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(), abs(date.timeIntervalSince(request.date)) < 1 {
                count += 1; continue
            }
            var components = PivotDate.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.date)
            components.timeZone = PivotDate.calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do { try await center.add(.init(identifier: request.id, content: content, trigger: trigger)); count += 1 }
            catch { status = "Alcuni avvisi non sono stati programmati: \(error.localizedDescription)"; return }
        }
        let missingPlaces = LessonLogistics.pendingEffective(events: events, data: data, now: Date())
        let validPlaceIDs = Set(missingPlaces.map { "lesson-place-\($0.id)" })
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("lesson-place-") && !validPlaceIDs.contains($0.identifier) }.map(\.identifier))
        // Once per discovered occurrence, not every minute while it remains unanswered.
        let retainedPlaceCount = pending.filter { $0.identifier.hasPrefix("lesson-place-") && validPlaceIDs.contains($0.identifier) }.count
        for event in missingPlaces.filter({ !lastLessonPromptIDs.contains($0.id) }).prefix(max(0, 3 - retainedPlaceCount)) {
            let content = UNMutableNotificationContent()
            content.title = "Dove fai questa lezione?"
            content.body = "\(PivotDate.shortDate(event.start)) \(PivotDate.time(event.start)) · \(event.title). Apri Pivot per confermare chi si sposta."
            content.sound = .default
            content.userInfo = ["eventID": event.id, "destination": "event"]
            do {
                try await center.add(.init(identifier: "lesson-place-\(event.id)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
                lastLessonPromptIDs.insert(event.id)
            } catch { status = "Avviso luogo non programmato: \(error.localizedDescription)" }
        }
        // Pending requests are reconciled above. Also remove an already shown
        // event question when its calendar occurrence no longer exists.
        let currentEvents = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
        let now = Date()
        let delivered = await center.deliveredNotifications()
        let staleDelivered = delivered.compactMap { notification -> String? in
            if notification.request.identifier.hasPrefix("savings-weekly-") {
                return wanted.contains(notification.request.identifier) ? nil : notification.request.identifier
            }
            let eventID = notification.request.content.userInfo["eventID"] as? String ?? ""
            guard !eventID.isEmpty else { return nil }
            guard let event = currentEvents[eventID] else { return notification.request.identifier }
            if [.completed, .partial, .skipped].contains(data.records[eventID]?.status ?? .pending) {
                return notification.request.identifier
            }
            // A result question delivered before the occurrence now ends can
            // only belong to its previous schedule.
            if notification.request.identifier.hasPrefix("event-") && event.end > now {
                return notification.request.identifier
            }
            return nil
        }
        center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
        await incomeWarning(data: data, center: center)
        status = weeklyWarning ?? "\(count) avvisi nelle prossime 36 ore e \(weekly.count) promemoria settimanali. Calendario riconciliato quando Pivot si aggiorna. Full immersion può silenziarli."
    }
    private func incomeWarning(data: AppData, center: UNUserNotificationCenter) async {
        let ledger = data.ledger ?? AnnualLedger()
        let year = PivotDate.calendar.component(.year, from: Date())
        let total = ledger.total(year: year, payments: data.payments)
        guard let band = ledger.band(total: total) else { return }
        let key = "income-\(year)-\(ledger.referenceCents)-\(band)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let content = UNMutableNotificationContent()
        content.title = band == "reference" ? "Incassi: riferimento INPS raggiunto" : "Incassi: ti avvicini al riferimento INPS"
        content.body = "\(Money.display(total)) incassati nel \(year). I 5.000 € non sono un limite esente da tasse. Verifica gli adempimenti e l'inquadramento delle ripetizioni."
        content.sound = .default
        do {
            try await center.add(.init(identifier: key, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
            UserDefaults.standard.set(true, forKey: key)
        } catch { status = "Avviso incassi non programmato: \(error.localizedDescription)" }
    }

}
