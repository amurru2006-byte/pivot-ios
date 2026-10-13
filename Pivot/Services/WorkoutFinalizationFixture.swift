#if DEBUG && targetEnvironment(simulator)
import Foundation
import PDFKit

@MainActor
enum WorkoutFinalizationFixture {
    static func verify() async throws -> String {
        let store = WorkoutRuntime.store
        guard let saved = store.data.training?.sessions.first(where: { $0.id == Serie7Fixture.sessionID }),
              let end = saved.end, saved.rest == nil, await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
        var stale = saved; stale.notes = "STALE_VIEW_MUST_NOT_LEAK"
        let first = try await store.trainingExportURL(stale)
        let second = try await store.trainingExportURL(saved)
        guard first == second, first.deletingLastPathComponent().lastPathComponent == "TrainingReports",
              let document = PDFDocument(url: first), document.pageCount > 0,
              let text = document.string, text.contains("Cable Crunch"), text.contains(PivotDate.time(end)),
              !text.contains("STALE_VIEW_MUST_NOT_LEAK"), !text.contains("in corso"),
              store.data.training?.sessions.first(where: { $0.id == saved.id })?.end == end else { throw TrainingError.invalidPlan }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try Data(contentsOf: first).write(to: folder.appendingPathComponent("Pivot-QA-finalization.pdf"), options: .atomic)
        return "PDF finale verificato · fine \(Int(end.timeIntervalSince1970))"
    }
}
#endif
