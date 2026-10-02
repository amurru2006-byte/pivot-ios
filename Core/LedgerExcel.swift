import Foundation

// A real .xlsx workbook, using only Foundation. Cells with user text are inline strings,
// never formulas. All source entries and payments remain in the backup.
enum LedgerExcel {
    enum Cell { case text(String), number(Int), money(Int) }
    static func make(data: AppData, year: Int) -> Data {
        let ledger = data.ledger ?? AnnualLedger()
        let payments = data.payments.filter { PivotDate.calendar.component(.year, from: $0.date) == year }.sorted { $0.date < $1.date }
        // Include lessons from previous years if they were paid in the selected year.
        let paymentIDs = Set(payments.map(\.incomeID))
        let lessons = data.income.filter { PivotDate.calendar.component(.year, from: $0.date) == year || paymentIDs.contains($0.id) }.sorted { $0.date < $1.date }
        let summary: [[Cell]] = [
            [.text("Registro personale Pivot"), .number(year)],
            [.text("Incassato nell'anno"), .money(ledger.total(year: year, payments: data.payments))],
            [.text("Importo pregresso aggregato"), .money(ledger.openingCents[String(year)] ?? 0)],
            [.text("Pagamenti registrati nell'anno"), .money(payments.reduce(0) { $0 + $1.amountCents })],
            [.text("Da incassare: tutte le lezioni"), .money(data.income.reduce(0) { $0 + $1.outstandingCents })],
            [.text("Creato il"), .text(PivotDate.key(Date()))],
            [.text("Importante"), .text("Il saldo iniziale è un aggregato senza dettaglio dei singoli pagamenti. Questo registro personale non sostituisce ricevute, fatture o dichiarazione fiscale.")],
            [.text("Fiscalità"), .text(AnnualLedger.fiscalExplanation)],
            [.text("Fonte INPS"), .text(AnnualLedger.sourceURL)]
        ]
        var receipts: [[Cell]] = [[.text("ID pagamento"), .text("Data incasso"), .text("Studente"), .text("ID lezione"), .text("Incasso EUR")]]
        receipts += payments.map { [.text($0.id.uuidString), .text(PivotDate.key($0.date)), .text($0.clientName), .text($0.incomeID.uuidString), .money($0.amountCents)] }
        var rows: [[Cell]] = [[.text("ID lezione"), .text("Data lezione"), .text("Studente"), .text("Minuti"), .text("Importo EUR"), .text("Pagato totale EUR"), .text("Da incassare EUR"), .text("Evento calendario"), .text("Note")]]
        rows += lessons.map { [.text($0.id.uuidString), .text(PivotDate.key($0.date)), .text($0.clientName), .number($0.minutes), .money($0.amountCents), .money($0.paidCents), .money($0.outstandingCents), .text($0.calendarEventID ?? ""), .text($0.notes)] }
        let ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let parts: [(String, String)] = [
            ("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" + (1...3).map { "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined() + "</Types>"),
            ("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            ("xl/workbook.xml", "<workbook xmlns=\"\(ns)\" xmlns:r=\"\(rel)\"><sheets><sheet name=\"Riepilogo\" sheetId=\"1\" r:id=\"rId1\"/><sheet name=\"Incassi\" sheetId=\"2\" r:id=\"rId2\"/><sheet name=\"Lezioni\" sheetId=\"3\" r:id=\"rId3\"/></sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + (1...3).map { "<Relationship Id=\"rId\($0)\" Type=\"\(rel)/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>" }.joined() + "<Relationship Id=\"rId4\" Type=\"\(rel)/styles\" Target=\"styles.xml\"/></Relationships>"),
            ("xl/styles.xml", "<styleSheet xmlns=\"\(ns)\"><numFmts count=\"1\"><numFmt numFmtId=\"164\" formatCode=\"0.00\"/></numFmts><fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"164\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"),
            ("xl/worksheets/sheet1.xml", sheet(summary)), ("xl/worksheets/sheet2.xml", sheet(receipts)), ("xl/worksheets/sheet3.xml", sheet(rows))
        ]
        return archive(parts.map { ($0.0, Data($0.1.utf8)) })
    }
    private static func xml(_ s: String) -> String {
        let clean = String(s.unicodeScalars.filter { $0.value >= 32 || [9,10,13].contains($0.value) })
        return clean.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func sheet(_ rows: [[Cell]]) -> String {
        var body = ""
        for (r, row) in rows.enumerated() {
            body += "<row r=\"\(r+1)\">"
            for (c, cell) in row.enumerated() {
                let ref = "\(Character(UnicodeScalar(65+c)!))\(r+1)"
                switch cell {
                case .text(let s): body += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(s))</t></is></c>"
                case .number(let n): body += "<c r=\"\(ref)\"><v>\(n)</v></c>"
                case .money(let n): body += "<c r=\"\(ref)\" s=\"1\"><v>\(n / 100).\(String(format: "%02d", n % 100))</v></c>"
                }
            }
            body += "</row>"
        }
        return "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews><cols><col min=\"1\" max=\"9\" width=\"25\" customWidth=\"1\"/></cols><sheetData>\(body)</sheetData></worksheet>"
    }
    private static func archive(_ files: [(String, Data)]) -> Data {
        var out = Data(), central = Data()
        func le(_ n: UInt32, _ width: Int = 4) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: n >> ($0*8)) }) }
        for (name, bytes) in files {
            let path = Data(name.utf8), crc = crc32(bytes), length = UInt32(bytes.count), offset = UInt32(out.count)
            for chunk in [le(0x04034b50), le(20,2), le(0,2), le(0,2), le(0,2), le(33,2), le(crc), le(length), le(length), le(UInt32(path.count),2), le(0,2) , path, bytes] { out.append(chunk) }
            for chunk in [le(0x02014b50), le(20,2), le(20,2), le(0,2), le(0,2), le(0,2), le(33,2), le(crc), le(length), le(length), le(UInt32(path.count),2), le(0,2), le(0,2), le(0,2), le(0,2), le(0), le(offset) , path] { central.append(chunk) }
        }
        let offset = UInt32(out.count)
        out += central
        out += le(0x06054b50) + le(0,2) + le(0,2) + le(UInt32(files.count),2) + le(UInt32(files.count),2) + le(UInt32(central.count)) + le(offset) + le(0,2)
        return out
    }
    private static func crc32(_ bytes: Data) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in bytes {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb88320 : 0) }
        }
        return value ^ 0xffffffff
    }
}
