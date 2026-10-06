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
        await MainActor.run { self.route = Route(eventID: eventID, destination: destination, outcome: outcome, clientID: clientID) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list, .sound] }
    @Published private(set) var status = "Notifiche non configurate"
    private var generation = 0
    private var lastLessonPromptIDs: Set<String> = []
    func requestAccess() async {
        do {
            let ok = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            status = ok ? "Notifiche autorizzate" : "Notifiche negate: abilita Pivot nelle impostazioni di iOS"
        } catch { status = error.localizedDescription }
    }
    func schedule(events: [CalendarItem], data: AppData) async {
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
        let reserved = pending.filter { $0.identifier.hasPrefix("income-") }.count
        let requests = await Task.detached(priority: .utility) {
            NotificationPlan.requestsFromPlanned(events: events, data: data, now: Date(), capacity: min(57, max(0, 60 - reserved)))
        }.value
        guard token == generation else { return }
        let wanted = Set(requests.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !$0.identifier.hasPrefix("income-") && !$0.identifier.hasPrefix("lesson-place-") && !wanted.contains($0.identifier) }.map(\.identifier))
        let existing = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { _, newer in newer })
        var count = 0
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
               let date = old.trigger?.nextTriggerDate(), abs(date.timeIntervalSince(request.date)) < 1 {
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
        await incomeWarning(data: data, center: center)
        status = "\(count) avvisi programmati, entro 7 giorni e nei limiti della coda iOS. Apri Pivot dopo modifiche al calendario. Full immersion può silenziarli."
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
