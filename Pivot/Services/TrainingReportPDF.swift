import Foundation
import UIKit
import CoreText

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
        let renderer = UIGraphicsPDFRenderer(bounds: ReportCanvas.bounds)
        return renderer.pdfData { context in
            let page = ReportCanvas(context)
            page.begin()
            page.hero(title)
            if let interval {
                let last = PivotDate.calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
                page.text("\(PivotDate.shortDate(interval.start)) – \(PivotDate.shortDate(last)) · \(sessions.count) allenamenti svolti", size: 11, color: ReportCanvas.muted)
                page.text("Solo allenamenti con lavoro registrato. Serie fatte, non svolte e da fare sono distinte nelle tabelle.", size: 9, color: ReportCanvas.muted)
            }
            for (si, session) in sessions.enumerated() {
                if si > 0 { page.begin() }
                let plan = library.plans.first { $0.id == session.planID }?.payload.name ?? "Scheda registrata nel diario"
                page.ensure(118)
                page.text(session.dayName, size: 23, weight: .bold, color: ReportCanvas.ink)
                page.text(plan, size: 11, weight: .medium, color: ReportCanvas.accent)
                let done = session.exercises.flatMap(\.sets).filter(\.done).count
                let skipped = session.exercises.reduce(0) { $0 + ($1.skipped == true ? $1.sets.count : $1.sets.filter { $0.skipped == true }.count) }
                page.summary([
                    ("DATA", PivotDate.shortDate(session.start)),
                    ("INIZIO / FINE", "\(PivotDate.time(session.start)) / \(session.end.map(PivotDate.time) ?? "in corso")"),
                    ("DURATA TOTALE", session.end.map { ActivityTiming.duration(max(0, Int($0.timeIntervalSince(session.start)))) } ?? "in corso")
                ])
                page.text("\(session.exercises.count) esercizi · \(done) serie fatte · \(skipped) non svolte", size: 10, color: ReportCanvas.muted)
                for (ei, log) in session.exercises.enumerated() {
                    let heading = "\(ei + 1). \(log.exercise.name)"
                    page.ensure(100); page.y += 8
                    page.text(heading, size: 15, weight: .bold, color: ReportCanvas.accent, gap: 4)
                    page.text("Programma: \(log.exercise.sets) serie × \(log.exercise.reps) · Recupero base: \(log.exercise.restSeconds) s", size: 10, color: ReportCanvas.muted, gap: 6)
                    if !log.exercise.coachNotes.isEmpty { page.note("INDICAZIONI PT", log.exercise.coachNotes) }
                    if let reason = log.skipReason { page.note(log.skipped == true ? "ESERCIZIO NON SVOLTO" : "SERIE NON SVOLTE", reason) }
                    if log.skipped == true && log.skipReason == nil { page.text("ESERCIZIO NON SVOLTO", size: 10, weight: .semibold, color: ReportCanvas.muted) }
                    page.ensureTableSpace(heading)
                    page.tableHeader()
                    for (row, set) in log.sets.enumerated() {
                        let isSkipped = log.skipped == true || set.skipped == true
                        let status = isSkipped ? "NON SVOLTA" : set.done ? "FATTA" : "DA FARE"
                        let group = (set.supersetGroup ?? "").isEmpty ? "" : " · gruppo " + set.supersetGroup!
                        let kind = set.resolvedKind.label + group + (set.reachesFailure ? " · cedimento" : "") + (set.isAdditional == true ? " · extra" : "")
                        let performance = isSkipped ? (set.explicitlySkippedHold(log.exercise)
                            ? (log.exercise.separateSides == true ? "Sx 0 s / Dx 0 s" : "0 s") : "—")
                            : TrainingReports.performance(set, exercise: log.exercise)
                        let cells = [
                            String(set.number), kind,
                            performance,
                            "Prev. \(set.restSeconds ?? log.exercise.restSeconds) s\nEff. \(set.actualRestSeconds.map { "\($0) s" } ?? "—")",
                            set.completedAt.map(PivotDate.time) ?? "—", status
                        ]
                        page.tableRow(cells, striped: row.isMultiple(of: 2), done: set.done, heading: heading)
                        if let kg = set.legacyKG, let reps = set.legacyReps {
                            page.text("Conversione isometria: originale conservato \(kg.formatted()) kg × \(reps).", size: 9, color: ReportCanvas.muted)
                        }
                    }
                    page.y += 6
                    if let last = library.previous(exerciseID: log.id, before: session.start, excluding: session.id) {
                        page.note("PRECEDENTE", last.sets.filter(\.done).map { TrainingReports.performance($0, exercise: last.exercise) }.joined(separator: "; "))
                    }
                    if !log.notes.isEmpty { page.note("NOTE SESSIONE / REGOLAZIONI MACCHINA", log.notes) }
                    if let tip = library.tips[log.id], !tip.isEmpty { page.note("PROMEMORIA PERSONALI", tip) }
                }
                if !session.notes.isEmpty { page.note("NOTE ALLENAMENTO", session.notes) }
            }
        }
    }
}

/// A4, fixed table columns and measured line wrapping. Continuations repeat
/// exercise titles and table headers; long notes paginate without truncation.
private final class ReportCanvas {
    static let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
    static let ink = UIColor(red: 0.09, green: 0.15, blue: 0.20, alpha: 1)
    static let muted = UIColor(red: 0.36, green: 0.41, blue: 0.46, alpha: 1)
    static let accent = UIColor(red: 0.04, green: 0.36, blue: 0.31, alpha: 1)
    private let context: UIGraphicsPDFRendererContext
    private let width: CGFloat = 523
    private let columns: [CGFloat] = [28, 104, 142, 104, 59, 86]
    private var number = 0
    var y: CGFloat = 70
    init(_ context: UIGraphicsPDFRendererContext) { self.context = context }
    func begin() {
        context.beginPage(); number += 1; y = 70
        UIColor.white.setFill(); context.cgContext.fill(Self.bounds)
        draw("PIVOT", x: 36, y: 24, size: 15, weight: .heavy, color: Self.accent)
        draw("DIARIO DI ALLENAMENTO", x: 110, y: 28, size: 9, weight: .semibold, color: Self.muted)
        line(at: 52)
        draw("Per il personal trainer · Recupero previsto / effettivo in secondi · — = non registrato", x: 36, y: 801, size: 8, color: Self.muted)
        draw(String(number), x: 548, y: 801, size: 9, weight: .semibold, color: Self.accent)
    }
    func ensure(_ height: CGFloat) { if y + height > 782 { begin() } }
    func hero(_ title: String) {
        let lines = wrapped(title, font: .systemFont(ofSize: 25, weight: .bold), width: width - 28)
        if lines.count > 3 { text(title, size: 25, weight: .bold); return }
        let height = CGFloat(lines.count) * 30 + 28
        Self.ink.setFill(); UIBezierPath(roundedRect: CGRect(x: 36, y: y, width: width, height: height), cornerRadius: 12).fill()
        for (index, value) in lines.enumerated() { draw(value, x: 50, y: y + 14 + CGFloat(index) * 30, size: 25, weight: .bold, color: .white) }
        y += height + 16
    }
    func summary(_ values: [(String, String)]) {
        let cardWidth = (width - 16) / 3
        for (i, value) in values.enumerated() {
            let x = 36 + CGFloat(i) * (cardWidth + 8)
            UIColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: y, width: cardWidth, height: 47), cornerRadius: 8).fill()
            draw(value.0, x: x + 10, y: y + 8, size: 8, weight: .semibold, color: Self.accent)
            draw(value.1, x: x + 10, y: y + 23, size: 11, weight: .semibold, color: Self.ink)
        }
        y += 57
    }
    func text(_ value: String, size: CGFloat = 10, weight: UIFont.Weight = .regular, color: UIColor = ReportCanvas.ink, gap: CGFloat = 7) {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        for value in wrapped(value, font: font, width: width) {
            ensure(font.lineHeight + 3)
            draw(value, x: 36, y: y, size: size, weight: weight, color: color)
            y += font.lineHeight + 3
        }
        y += gap
    }
    func note(_ label: String, _ value: String) {
        guard !value.isEmpty else { return }
        ensure(35)
        text(label, size: 8, weight: .bold, color: Self.accent, gap: 2)
        text(value, size: 9, color: Self.muted, gap: 7)
    }
    func ensureTableSpace(_ heading: String) {
        if y + 64 > 782 { begin(); text(heading + " · continua", size: 14, weight: .bold, color: Self.accent) }
    }
    func tableHeader() {
        Self.accent.setFill(); context.cgContext.fill(CGRect(x: 36, y: y, width: width, height: 23))
        var x: CGFloat = 36
        for (i, title) in ["SET", "TIPO / INTENSITÀ", "PRESTAZIONE", "RECUPERO", "ORA", "STATO"].enumerated() {
            draw(title, x: x + 5, y: y + 7, size: 7, weight: .bold, color: .white); x += columns[i]
        }
        y += 23
    }
    func tableRow(_ cells: [String], striped: Bool, done: Bool, heading: String) {
        let lines = cells.enumerated().map {
            wrapped($0.element, font: .systemFont(ofSize: 9, weight: $0.offset == 2 || $0.offset == 5 ? .semibold : .regular), width: columns[$0.offset] - 10)
        }
        let height = max(34, CGFloat(lines.map(\.count).max() ?? 1) * 13 + 12)
        if y + height > 782 { begin(); text(heading + " · continua", size: 14, weight: .bold, color: Self.accent); tableHeader() }
        if striped {
            UIColor(white: 0.96, alpha: 1).setFill(); context.cgContext.fill(CGRect(x: 36, y: y, width: width, height: height))
        }
        var x: CGFloat = 36
        for i in cells.indices {
            for (j, value) in lines[i].enumerated() {
                draw(value, x: x + 5, y: y + 6 + CGFloat(j) * 13, size: 9,
                     weight: i == 2 || i == 5 ? .semibold : .regular,
                     color: i == 5 && done ? Self.accent : i >= 3 ? Self.muted : Self.ink)
            }
            x += columns[i]
        }
        y += height
        line(at: y)
    }
    private func line(at y: CGFloat) {
        context.cgContext.setStrokeColor(UIColor(white: 0.88, alpha: 1).cgColor); context.cgContext.setLineWidth(0.5)
        context.cgContext.move(to: CGPoint(x: 36, y: y)); context.cgContext.addLine(to: CGPoint(x: 559, y: y)); context.cgContext.strokePath()
    }
    private func draw(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor) {
        (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
    private func wrapped(_ value: String, font: UIFont, width: CGFloat) -> [String] {
        var result: [String] = []
        for paragraph in value.components(separatedBy: "\n") {
            if paragraph.isEmpty { result.append(""); continue }
            let string = paragraph as NSString
            let attributed = NSAttributedString(string: paragraph, attributes: [.font: font])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed as CFAttributedString)
            var offset = 0
            while offset < string.length {
                var count = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
                if count == 0 { count = max(1, CTTypesetterSuggestClusterBreak(typesetter, offset, Double(width))) }
                result.append(string.substring(with: NSRange(location: offset, length: count)).trimmingCharacters(in: .whitespaces))
                offset += count
            }
        }
        return result
    }
}
