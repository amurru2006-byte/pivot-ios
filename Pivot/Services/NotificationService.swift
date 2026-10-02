import UserNotifications
import Foundation
import Combine

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list, .sound] }
    @Published private(set) var status = "Notifiche non configurate"
    private var generation = 0
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
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !$0.identifier.hasPrefix("income-") }.map(\.identifier))
        let now = Date()
        let horizon = now.addingTimeInterval(48 * 3600)
        let calendar = PivotDate.calendar
        var requests: [(Date, String, String, String)] = []
        func add(_ date: Date, _ id: String, _ title: String, _ body: String) {
            guard date > now, date < horizon else { return }
            let hour = calendar.component(.hour, from: date)
            guard hour >= data.settings.quietEndHour && hour < data.settings.quietStartHour else { return }
            requests.append((date, id, title, body))
        }
        for event in events where !event.isAllDay {
            let record = data.records[event.id]
            let missingCompensation = event.kind == .tutoring && [Completion.completed, .partial].contains(record?.status ?? .pending)
                && record?.tutoringAnswered != true && !data.income.contains(where: { $0.calendarEventID == event.id || $0.id == record?.incomeID })
            guard missingCompensation || (record?.status != .completed && record?.status != .partial && record?.status != .skipped) else { continue }
            if event.kind == .meal {
                for minutes in [30, 10] {
                    add(event.start.addingTimeInterval(-Double(minutes) * 60), "meal-\(event.id)-\(minutes)", event.title, "Tra \(minutes) minuti. Apri Pivot per le indicazioni del pasto.")
                }
            }
            if event.title.lowercased().contains("sveglia") {
                let day = PivotDate.key(event.start)
                let didStart = data.records.values.contains { PivotDate.key($0.snapshot.start) == day && $0.actualStart != nil }
                if !didStart && data.checkIns[day]?.wakeTime == nil {
                    add(event.start.addingTimeInterval(Double(data.settings.morningDelayMinutes) * 60), "morning-\(day)", "Come è iniziata la giornata?", "Registra la sveglia reale, l'energia e l'umore dopo la routine.")
                }
                continue
            }
            // Sleep/relax blocks do not generate an hourly questionnaire cascade.
            guard event.kind != .routine else { continue }
            add(event.end, "event-\(event.id)-0", "\(event.title): com'è andata?", "Segna fatto, parziale o saltato e aggiungi le tue note.")
            add(event.end.addingTimeInterval(1800), "event-\(event.id)-30", "Manca il resoconto", "Devi ancora compilare: \(event.title). Puoi farlo quando sei libero.")
            if data.settings.repeatMissedNotifications {
                for hour in 1...24 {
                    add(event.end.addingTimeInterval(1800 + Double(hour) * 3600), "event-\(event.id)-\(hour)", "Resoconto ancora da compilare", event.title)
                }
            }
        }
        for day in 0...2 {
            let date = calendar.date(byAdding: .day, value: day, to: now)!
            let time = calendar.date(bySettingHour: data.settings.eveningHour, minute: data.settings.eveningMinute, second: 0, of: date)!
            add(time, "evening-\(PivotDate.key(date))", "Resoconto della giornata", "Apri Pivot: controlla le risposte mancanti e condividi il resoconto con ChatGPT.")
        }
        var count = 0
        for request in requests.sorted(by: { $0.0 < $1.0 }).prefix(60) {
            guard token == generation, !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = request.2
            content.body = request.3
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.0.timeIntervalSinceNow), repeats: false)
            do { try await center.add(.init(identifier: request.1, content: content, trigger: trigger)); count += 1 }
            catch { status = "Alcuni avvisi non sono stati programmati: \(error.localizedDescription)"; return }
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
