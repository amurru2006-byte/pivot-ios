import UserNotifications
import Foundation
import Combine

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
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
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !$0.identifier.hasPrefix("income-") && !$0.identifier.hasPrefix("lesson-place-") }.map(\.identifier))
        let reserved = pending.filter { $0.identifier.hasPrefix("income-") }.count
        let requests = NotificationPlan.requests(events: events, data: data, now: Date(), capacity: min(57, max(0, 60 - reserved)))
        var count = 0
        for request in requests {
            guard token == generation, !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.date.timeIntervalSinceNow), repeats: false)
            do { try await center.add(.init(identifier: request.id, content: content, trigger: trigger)); count += 1 }
            catch { status = "Alcuni avvisi non sono stati programmati: \(error.localizedDescription)"; return }
        }
        let missingPlaces = LessonLogistics.pending(events: events, data: data, now: Date())
        let validPlaceIDs = Set(missingPlaces.map { "lesson-place-\($0.id)" })
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("lesson-place-") && !validPlaceIDs.contains($0.identifier) }.map(\.identifier))
        // Once per discovered occurrence, not every minute while it remains unanswered.
        for event in missingPlaces.filter({ !lastLessonPromptIDs.contains($0.id) }).prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = "Dove fai questa lezione?"
            content.body = "\(PivotDate.shortDate(event.start)) \(PivotDate.time(event.start)) · \(event.title). Apri Pivot per confermare chi si sposta."
            content.sound = .default
            do {
                try await center.add(.init(identifier: "lesson-place-\(event.id)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
                lastLessonPromptIDs.insert(event.id)
            } catch { status = "Avviso luogo non programmato: \(error.localizedDescription)" }
        }
        await incomeWarning(data: data, center: center)
        status = "\(count) avvisi programmati, fino a 48 ore. Apri Pivot ogni giorno per aggiornarli. Full immersion e impostazioni di iOS possono ritardare o silenziare gli avvisi."
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
