import SwiftUI
import Charts

struct ClientIncomeOverview: View {
    private enum Range: String, CaseIterable { case month = "Mese", year = "Anno", all = "Tutto" }
    private enum Style: String, CaseIterable { case bars = "Barre", line = "Linea", area = "Area" }
    @EnvironmentObject private var store: PivotStore
    let clientID: UUID
    @State private var range: Range = .year
    @State private var year = PivotDate.calendar.component(.year, from: Date())
    @State private var month = PivotDate.calendar.component(.month, from: Date())
    @State private var page = 0
    @State private var style: Style = .bars
    @State private var pageHeights: [Int: CGFloat] = [:]
    @State private var selectedBar: String?
    private let monthLabels = ["Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"]
    private var payments: [Payment] { IncomeAnalytics.receipts(clientID: clientID, data: store.data) }
    private var years: [Int] { Array(Set([PivotDate.calendar.component(.year, from: Date())] + payments.compactMap(\.year))).sorted(by: >) }
    private var period: IncomeAnalytics.Period {
        switch range { case .all: return .all; case .year: return .year(year); case .month: return .month(year: year, month: month) }
    }
    private var received: Int? { try? IncomeAnalytics.total(payments, period: period) }
    private var outstanding: Int? { try? IncomeAnalytics.outstanding(clientID: clientID, data: store.data) }
    private var undated: Int { (try? IncomeAnalytics.undated(year: year, payments: payments)) ?? 0 }
    private var points: [IncomeAnalytics.Month]? { try? IncomeAnalytics.months(year: year, payments: payments) }
    private var height: CGFloat { pageHeights[page] ?? (page == 0 ? 220 : 320) }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Incassi del contatto", selection: $range) { ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).accessibilityIdentifier("client-income-period")
            HStack {
                Button("Oggi") {
                    let now = PivotDate.calendar.dateComponents([.year, .month], from: Date())
                    year = now.year ?? year; month = now.month ?? month
                    selectedBar = nil
                }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityIdentifier("client-income-today")
                if range == .month {
                    Picker("Mese", selection: $month) { ForEach(1...12, id: \.self) { Text(monthLabels[$0 - 1]).tag($0) } }
                        .accessibilityIdentifier("client-income-month")
                }
                Spacer()
                Picker("Anno", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }
                    .accessibilityIdentifier("client-income-year")
            }
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        measured(0, width: geometry.size.width) { summary }.id(0).accessibilityHidden(page != 0)
                        measured(1, width: geometry.size.width) { graph }.id(1).accessibilityHidden(page != 1)
                    }.scrollTargetLayout()
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .scrollIndicators(.hidden).scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding<Int?>(get: { page }, set: { if let value = $0 { page = value } }))
                    .accessibilityIdentifier("client-income-carousel")
            }.frame(height: height)
            HStack(spacing: 24) {
                pageButton("Riepilogo", value: 0)
                pageButton("Grafico", value: 1)
            }
        }.onChange(of: year) { _, _ in selectedBar = nil }
            .onChange(of: month) { _, _ in selectedBar = nil }
            .onChange(of: range) { _, _ in selectedBar = nil }
            .onChange(of: style) { _, _ in selectedBar = nil }
            .onChange(of: clientID) { _, _ in selectedBar = nil }
    }
    private func measured<Content: View>(_ page: Int, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content().frame(width: width, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                guard measured.isFinite, measured > 0, abs((pageHeights[page] ?? 0) - measured) > 1 else { return }
                pageHeights[page] = measured
            }
    }
    private func pageButton(_ title: String, value: Int) -> some View {
        Button { withAnimation { page = value } } label: {
            HStack(spacing: 6) {
                Circle().fill(page == value ? PivotTheme.accent : PivotTheme.muted).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(page == value ? .semibold : .regular))
            }.foregroundStyle(page == value ? PivotTheme.accent : PivotTheme.muted).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(page == value ? .isSelected : [])
            .accessibilityIdentifier("client-income-page-\(value)")
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(range == .month ? "Ricevuto nel mese" : range == .year ? "Ricevuto nell’anno" : "Ricevuto totale", systemImage: "eurosign.circle.fill")
                .font(.subheadline).foregroundStyle(PivotTheme.accent)
            if let received {
                Text(Money.display(received)).font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(PivotTheme.accent).accessibilityIdentifier("client-income-received")
            } else { Text("Importi da verificare").foregroundStyle(PivotTheme.amber) }
            HStack {
                Text(range == .all ? "Tutto lo storico" : range == .month ? "\(monthLabels[month - 1]) \(year)" : String(year))
                    .foregroundStyle(PivotTheme.muted)
                Spacer()
                Text("Da incassare \(outstanding.map(Money.display) ?? "—")").foregroundStyle(PivotTheme.amber)
                    .accessibilityIdentifier("client-income-outstanding")
            }.font(.caption)
            if undated > 0 && range == .month {
                Text("\(Money.display(undated)) nell’anno senza data d’incasso").font(.caption).foregroundStyle(PivotTheme.muted)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [Color(pivotHex: "22493F"), Color(pivotHex: "1C2C41"), PivotTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(PivotTheme.accent.opacity(0.18)))
            .accessibilityElement(children: .contain)
    }
    private var graph: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Andamento incassi · \(year)", systemImage: "chart.xyaxis.line").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.blue)
                Spacer()
                Picker("Grafico", selection: $style) { ForEach(Style.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .accessibilityIdentifier("client-income-chart-style")
            }
            if let points {
                if style == .bars, let point = points.first(where: { monthLabels[$0.id - 1] == selectedBar }) {
                    IncomeBarReadout(label: "\(monthLabels[point.id - 1]) \(year)", cents: point.cents,
                                     identifier: "client-income-bar-value") { selectedBar = nil }
                }
                Chart(points) { point in
                    switch style {
                    case .bars:
                        BarMark(x: .value("Mese", monthLabels[point.id - 1]), y: .value("Euro", point.euros))
                            .foregroundStyle(PivotTheme.blue.gradient).cornerRadius(4)
                            .opacity(selectedBar == nil || selectedBar == monthLabels[point.id - 1] ? 1 : 0.4)
                            .accessibilityLabel(Text("\(monthLabels[point.id - 1]) \(year)"))
                            .accessibilityValue(Text(Money.display(point.cents)))
                    case .line:
                        LineMark(x: .value("Mese", monthLabels[point.id - 1]), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue)
                        PointMark(x: .value("Mese", monthLabels[point.id - 1]), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue)
                    case .area:
                        AreaMark(x: .value("Mese", monthLabels[point.id - 1]), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue.opacity(0.3))
                        LineMark(x: .value("Mese", monthLabels[point.id - 1]), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue)
                    }
                }.chartYScale(domain: 0...max(1, (points.map(\.euros).max() ?? 0) * 1.15))
                    .chartXSelection(value: $selectedBar)
                    .chartGesture { proxy in
                        SpatialTapGesture().onEnded { value in
                            if style == .bars { proxy.selectXValue(at: value.location.x) }
                        }
                    }
                    .chartYAxisLabel("€").frame(height: 205).accessibilityIdentifier("client-income-chart")
            } else { Text("Importi da verificare").foregroundStyle(PivotTheme.amber) }
            if undated > 0 { Text("Senza data d’incasso: \(Money.display(undated))").font(.caption).foregroundStyle(PivotTheme.muted) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(PivotTheme.blue.opacity(0.2)))
            .accessibilityElement(children: .contain)
    }
}
