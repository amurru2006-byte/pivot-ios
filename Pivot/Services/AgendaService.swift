import Foundation
import Combine

@MainActor
final class AgendaService: ObservableObject {
    @Published private(set) var planned: [CalendarItem] = []
    @Published private(set) var effective: [CalendarItem] = []
    @Published private(set) var paymentDues: [PaymentDue] = []
    @Published private(set) var revision: UInt64 = 0
    private var request: UInt64 = 0
    private let gate = RefreshGate(delayNanoseconds: 80_000_000)

    func rebuild(events: [CalendarItem], hasAccess: Bool, store: PivotStore, diagnostics: PerformanceDiagnostics) {
        request &+= 1
        let token = request
        gate.request { [weak self, weak store] in
            guard let self, let store, !store.isLoading, !store.isRestoring else { return }
            let data = store.data, version = data.updatedAt, now = Date()
            let start = ProcessInfo.processInfo.systemUptime
            let snapshot = await Task.detached(priority: .userInitiated) {
                let effective = Planner.effectiveEvents(events, data: data)
                let planned = Planner.plannedEffectiveEvents(effective, data: data)
                let prompts = hasAccess ? LessonPromptState.observed(events, data: data, now: now) : data.lessonPrompts
                let decisions = hasAccess ? EventContext.refreshedPlanned(events: planned, data: data, now: now) : (data.decisions ?? [])
                let dues = StudentPayments.dues(planned: planned, data: data)
                var withDates = data
                let changedDates = StudentPayments.rememberDeadlines(dues, data: &withDates)
                return (effective, planned, prompts, decisions, dues, changedDates, withDates.income)
            }.value
            guard token == self.request, version == store.data.updatedAt else { return }
            if self.effective != snapshot.0 { self.effective = snapshot.0 }
            if self.planned != snapshot.1 { self.planned = snapshot.1 }
            if self.paymentDues != snapshot.4 { self.paymentDues = snapshot.4 }
            self.revision &+= 1
            diagnostics.record("Agenda", seconds: ProcessInfo.processInfo.systemUptime - start)
            if !store.locked, snapshot.2 != data.lessonPrompts || snapshot.3 != data.decisions || snapshot.5 {
                store.change { $0.lessonPrompts = snapshot.2; $0.decisions = snapshot.3; if snapshot.5 { $0.income = snapshot.6 } }
            }
        }
    }
}
