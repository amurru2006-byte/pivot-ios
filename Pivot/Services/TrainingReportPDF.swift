import Foundation
import UIKit

enum TrainingReportPDF {
    enum ExportError: LocalizedError {
        case empty
        var errorDescription: String? { "In questa settimana non ci sono allenamenti con serie svolte." }
    }
    static func write(sessions: [TrainingSession], library: TrainingLibrary, title: String, interval: DateInterval? = nil) throws -> URL {
        let data = render(sessions: sessions, library: library, title: title, interval: interval)
        let first = sessions.first?.start ?? Date()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pivot-\(interval == nil ? "allenamento" : "settimana")-\(PivotDate.key(first))-\(UUID().uuidString.prefix(8)).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
    static func render(sessions: [TrainingSession], library: TrainingLibrary, title: String, interval: DateInterval? = nil) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: UIGraphicsPDFRendererFormat())
        let ink = UIColor(white: 0.12, alpha: 1), muted = UIColor(white: 0.38, alpha: 1)
        let accent = UIColor(red: 0.08, green: 0.39, blue: 0.34, alpha: 1)
        return renderer.pdfData { context in
            var page = 0, y: CGFloat = 74
            func newPage() {
                context.beginPage(); page += 1; y = 74
                UIColor.white.setFill(); context.cgContext.fill(bounds)
                ("PIVOT  /  ALLENAMENTO" as NSString).draw(at: CGPoint(x: 38, y: 28), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: accent])
                ("Diario personale - Pagina \(page)" as NSString).draw(at: CGPoint(x: 38, y: 809), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: muted])
                context.cgContext.setStrokeColor(accent.withAlphaComponent(0.3).cgColor)
                context.cgContext.move(to: CGPoint(x: 38, y: 51)); context.cgContext.addLine(to: CGPoint(x: 557, y: 51)); context.cgContext.strokePath()
            }
            func ensure(_ height: CGFloat) { if y + height > 785 { newPage() } }
            func text(_ value: String, size: CGFloat = 11, weight: UIFont.Weight = .regular, color: UIColor? = nil, gap: CGFloat = 7) {
                guard !value.isEmpty else { return }
                let font = UIFont.systemFont(ofSize: size, weight: weight)
                let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color ?? ink, .paragraphStyle: paragraph]
                // Draw line by line, also handling long notes across pages.
                for paragraphText in value.components(separatedBy: "\n") {
                    var line = ""
                    let words = paragraphText.components(separatedBy: " ")
                    for word in words {
                        let candidate = line.isEmpty ? word : line + " " + word
                        if (candidate as NSString).size(withAttributes: [.font: font]).width > 519 && !line.isEmpty {
                            let h = font.lineHeight + 3; ensure(h)
                            (line as NSString).draw(in: CGRect(x: 38, y: y, width: 519, height: h), withAttributes: attributes); y += h
                            line = word
                        } else { line = candidate }
                    }
                    // An unusually long token must still wrap and paginate.
                    while !line.isEmpty {
                        var part = line
                        while (part as NSString).size(withAttributes: [.font: font]).width > 519 && part.count > 1 { part.removeLast() }
                        let h = font.lineHeight + 3; ensure(h)
                        (part as NSString).draw(in: CGRect(x: 38, y: y, width: 519, height: h), withAttributes: attributes); y += h
                        line = String(line.dropFirst(part.count))
                    }
                }
                y += gap
            }
            newPage()
            text(title, size: 25, weight: .bold, color: accent, gap: 10)
            if let interval {
                let last = PivotDate.calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
                text("\(PivotDate.shortDate(interval.start)) - \(PivotDate.shortDate(last)) · \(sessions.count) allenamenti svolti", size: 12, color: muted)
                text("Il report comprende solo allenamenti con almeno una serie fatta. Le serie non svolte restano distinguibili nel diario.", size: 10, color: muted)
            }
            for (si, session) in sessions.enumerated() {
                if si > 0 { newPage() }
                text(session.dayName, size: 21, weight: .bold, gap: 10)
                let planName = library.plans.first { $0.id == session.planID }?.payload.name ?? "Scheda registrata nel diario"
                text(planName, size: 12, weight: .semibold, color: accent)
                text("Data \(PivotDate.shortDate(session.start)) · Inizio \(PivotDate.time(session.start)) · Fine \(session.end.map(PivotDate.time) ?? "in corso")", size: 10, color: muted)
                if let end = session.end { text("Durata totale: \(ActivityTiming.duration(max(0, Int(end.timeIntervalSince(session.start)))))", size: 10, color: muted) }
                for (ei, log) in session.exercises.enumerated() {
                    ensure(105)
                    y += 8
                    text("\(ei + 1). \(log.exercise.name)", size: 15, weight: .bold, color: accent)
                    text("Programma: \(log.exercise.sets) serie x \(log.exercise.reps) · Recupero base: \(log.exercise.restSeconds) s", size: 10, color: muted)
                    if !log.exercise.coachNotes.isEmpty { text("Indicazioni PT: " + log.exercise.coachNotes, size: 10) }
                    for set in log.sets {
                        ensure(58)
                        let group = (set.supersetGroup ?? "").isEmpty ? "" : " · gruppo " + set.supersetGroup!
                        let failure = set.reachesFailure ? " · a cedimento" : ""
                        text("Serie \(set.number) · \(set.resolvedKind.label)\(group)\(failure) · \(set.done ? "FATTA" : "NON FATTA")", size: 10, weight: .semibold, gap: 2)
                        text(TrainingReports.performance(set, exercise: log.exercise), size: 12, weight: .medium, gap: 2)
                        text("Recupero previsto \(set.restSeconds ?? log.exercise.restSeconds) s · effettivo \(set.actualRestSeconds.map { "\($0) s" } ?? "non registrato")" + (set.completedAt.map { " · completata " + PivotDate.time($0) } ?? ""), size: 9, color: muted, gap: 7)
                        if let kg = set.legacyKG, let reps = set.legacyReps { text("Conversione isometria: originale conservato \(kg.formatted()) kg x \(reps).", size: 9, color: muted) }
                    }
                    if let last = library.previous(exerciseID: log.id, before: session.start, excluding: session.id) {
                        text("Confronto precedente: " + last.sets.filter(\.done).map { TrainingReports.performance($0, exercise: last.exercise) }.joined(separator: "; "), size: 10, color: muted)
                    }
                    if !log.notes.isEmpty { text("Note sessione / regolazioni macchina: " + log.notes, size: 10) }
                    if let tip = library.tips[log.id], !tip.isEmpty { text("Promemoria personali: " + tip, size: 10) }
                }
                if !session.notes.isEmpty { text("Note allenamento", size: 14, weight: .bold); text(session.notes) }
            }
        }
    }
}
