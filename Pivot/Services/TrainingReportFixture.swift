#if DEBUG && targetEnvironment(simulator)
import Foundation
import PDFKit
enum TrainingReportFixture {
    static func export() throws -> Int {
        let date = ISO8601DateFormatter().date(from: "2026-10-07T20:00:00+02:00")!
        let bench = TrainingExercise(id: "fixture-bench", name: "Panca piana con bilanciere", sets: 3, reps: "4-6", restSeconds: 120, coachNotes: "Presa e impostazione concordate con il PT.")
        var plank = TrainingExercise(id: "fixture-plank", name: "Copenhagen Plank", sets: 3, reps: "15-30 s per lato", restSeconds: 60, coachNotes: "Registra separatamente sinistra e destra.")
        plank.isometric = true; plank.separateSides = true
        let logs = [
            TrainingExerciseLog(exercise: bench, sets: [
                .init(number: 1, kg: 40, reps: 8, done: true, kind: .warmup, restSeconds: 45, actualRestSeconds: 51),
                .init(number: 2, kg: 70, reps: 5, done: true, kind: .working, toFailure: false, actualRestSeconds: 123),
                .init(number: 3, kg: 70, reps: 4, done: true, kind: .superset, toFailure: true, supersetGroup: "A", restSeconds: 0),
                .init(number: 4, kg: 60, reps: 6, done: true, kind: .backoff),
                .init(number: 5, kg: 40, reps: 10, done: false, kind: .dropSet)
            ], notes: "Regolazioni macchina: sedile 4, appoggio 2."),
            TrainingExerciseLog(exercise: plank, sets: [
                .init(number: 1, done: true, leftSeconds: 25, rightSeconds: 25, restSeconds: 40, actualRestSeconds: 43, legacyKG: 25, legacyReps: 2),
                .init(number: 2, done: true, leftSeconds: 30, rightSeconds: 28),
                .init(number: 3, done: false)
            ])
        ]
        var session = TrainingSession(planID: UUID(), dayName: "Squat / esempio sintetico", calendarEventID: nil, start: date, end: date.addingTimeInterval(4200), exercises: logs, notes: "Esempio di controllo qualità: non contiene dati personali.")
        let first = session
        session.id = UUID(); session.start = date.addingTimeInterval(86400); session.end = session.start.addingTimeInterval(4500); session.dayName = "Bench / esempio sintetico"
        let library = TrainingLibrary(sessions: [first, session], tips: [bench.id: String(repeating: "Promemoria di prova: posizione, controllo e regolazioni. ", count: 35)])
        let data = TrainingReportPDF.render(sessions: [first, session], library: library, title: "Riepilogo settimanale", interval: TrainingReports.week(containing: date))
        guard let document = PDFDocument(data: data), document.pageCount >= 2, let text = document.string,
              text.contains("2 allenamenti svolti"), text.contains("Sx 25 s"), text.contains("Recupero previsto"),
              !text.contains("Ale Murru") else { throw TrainingError.invalidPlan }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try data.write(to: folder.appendingPathComponent("Pivot-QA-report.pdf"), options: .atomic)
        return document.pageCount
    }
}
#endif
