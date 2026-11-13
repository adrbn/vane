import AlmanacCore
#if os(macOS)
import AppKit
#endif
import Charts
import SwiftUI

/// Metric detail: hero total vs previous period and last year, chart with releases and hover, table.
struct MetricDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var metric: Metric
    /// Shared with App Store and Usage, so a tile and the screen it opens show the same period.
    @AppStorage("period") private var days = 28
    @State private var lastYear = true
    @State private var territory = ""
    @State private var hover: Date?

    var body: some View {
        let d = MetricData(store: model.store, app: model.appId ?? "", metric: metric, days: days, territory: territory)
        let up = Change(metric, value: d.value, previous: d.previous).up
        let color = t.color(metric, up: up)
        let kind = metric.isAppStore ? String(localized: "App Store") : [.sessions, .crashes].contains(metric) ? String(localized: "Usage") : String(localized: "Sales")
        Screen(title: metric.title, subtitle: "\(model.app?.name ?? "") · \(kind)", inspector: true) {
            GlassSegments(options: [(7, String(localized: "7 Days")), (28, String(localized: "28 Days")), (90, String(localized: "90 Days")), (365, String(localized: "Year"))], selection: $days)
            GlassGroup {
                if metric.hasTerritories { territoryMenu(d) }
                Button { lastYear.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(lastYear ? t.onAccent : .clear)
                            .frame(width: 14, height: 14)
                            .background(lastYear ? t.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(lastYear ? .clear : t.label3, lineWidth: 1))
                        Text("Last year")
                    }
                    .font(t.font(13, .semibold)).padding(.horizontal, 10).frame(height: 28).contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            GlassGroup {
                let pinned = model.pinned.contains(metric)
                Button { model.togglePin(metric) } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(pinned ? t.accentText : t.label).frame(width: 30, height: 28).contentShape(Capsule())
                }
                .buttonStyle(.plain).help(pinned ? Text("Unpin from sidebar") : Text("Pin to sidebar"))
                GlassItem(label: String(localized: "Export CSV"), symbol: "square.and.arrow.up") { export(d) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                hero(d, color: color)
                chart(d, color: color)
                    .frame(height: 256)
                    .themedCard(padding: 20)
                table(d)
            }
        }
        .onAppear { model.chatContext = d.chatContext(model.app?.name ?? "") }
        .onChange(of: days) { model.chatContext = d.chatContext(model.app?.name ?? "") }
        .onChange(of: territory) { model.chatContext = d.chatContext(model.app?.name ?? "") }
    }

    // MARK: Toolbar

    private func territoryMenu(_ d: MetricData) -> some View {
        let codes = model.store.byTerritory(d.app, metric == .downloads || metric == .firstDownloads ? .firstDownloads : metric, from: d.from, to: d.to)
            .sorted { $0.value > $1.value }.prefix(40).map(\.key)
        return Menu {
            Button("All territories") { territory = "" }
            Divider()
            ForEach(codes, id: \.self) { c in Button(Territories.name(c)) { territory = c } }
        } label: {
            HStack(spacing: 6) {
                // Fixed width: the bar must not move to a second row when a longer country is picked (#1).
                (territory.isEmpty ? Text("All territories") : Text(verbatim: Territories.name(territory))).lineLimit(1)
                    .frame(width: 112, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label2)
            }
            .font(t.font(13, .semibold)).padding(.horizontal, 10).frame(height: 28).contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Hero

    private func hero(_ d: MetricData, color: Color) -> some View {
        let c = Change(metric, value: d.value, previous: d.previous, arrows: false)
        let ly = Change(metric, value: d.value, previous: d.lastYearValue, arrows: false)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(d.rangeName) · \(d.rangeLabel)").font(t.font(13)).foregroundStyle(t.label2).monospacedDigit()
            HStack(alignment: .bottom, spacing: 40) {
                VStack(alignment: .leading, spacing: 2) {
                    Text.tracked(MetricData.full(metric, d.value), t.heroTracking).font(t.heroFont).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Group {
                        if d.hasPrevious {
                            Text(c.text).foregroundStyle(c.color(t)).fontWeight(.bold) + Text(" vs previous \(d.periodNoun)").foregroundStyle(t.label2)
                        } else {
                            Text("No full \(d.periodNoun) before this to compare").foregroundStyle(t.label2)
                        }
                    }
                    .font(t.font(17)).monospacedDigit()
                }
                if lastYear {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Same period last year").font(t.font(13)).foregroundStyle(t.label2)
                        Text(d.hasLastYear ? MetricData.full(metric, d.lastYearValue) : "—")
                            .font(t.font(28, .semibold)).foregroundStyle(t.label2).monospacedDigit()
                        if d.hasLastYear {
                            (Text(ly.text).foregroundStyle(ly.color(t)).fontWeight(.bold) + Text(" this year").foregroundStyle(t.label2))
                                .font(t.font(13)).monospacedDigit()
                        } else {
                            Text("Not enough history yet").font(t.font(13)).foregroundStyle(t.label2)
                        }
                    }
                    .padding(.bottom, 4)
                }
                Spacer(minLength: 0)
                legend(color: color).padding(.bottom, 8)
            }
        }
    }

    private func legend(color: Color) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) { Capsule().fill(color).frame(width: 14, height: 2); Text("This year") }
            if lastYear {
                HStack(spacing: 6) {
                    Path { p in p.move(to: .init(x: 0, y: 1)); p.addLine(to: .init(x: 14, y: 1)) }
                        .stroke(t.label3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 14, height: 2)
                    Text("Last year")
                }
            }
            HStack(spacing: 6) {
                Path { p in p.move(to: .init(x: 1, y: 0)); p.addLine(to: .init(x: 1, y: 12)) }
                    .stroke(t.label2, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 2, height: 12)
                Text("Release")
            }
        }
        .font(t.font(11)).foregroundStyle(t.label2).lineLimit(1).fixedSize()
    }

    // MARK: Chart

    private func chart(_ d: MetricData, color: Color) -> some View {
        Chart {
            if lastYear {
                ForEach(d.rows.filter { $0.lastYear != nil }) { r in
                    LineMark(x: .value("Day", r.date), y: .value("Last year", r.lastYear ?? 0), series: .value("Series", "Last year"))
                        .foregroundStyle(t.label3).lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            ForEach(d.rows) { r in
                AreaMark(x: .value("Day", r.date), y: .value(metric.title, r.value), series: .value("Series", "This year"))
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", r.date), y: .value(metric.title, r.value), series: .value("Series", "This year"))
                    .foregroundStyle(color).lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(d.versions) { v in
                RuleMark(x: .value("Release", Day.date(v.day)))
                    .foregroundStyle(t.label2.opacity(0.5)).lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Text(v.version).font(t.font(10, .semibold)).foregroundStyle(t.label2)
                    }
            }
            if let hover, let r = d.rows.min(by: { abs($0.date.timeIntervalSince(hover)) < abs($1.date.timeIntervalSince(hover)) }) {
                let right = (d.rows.firstIndex { $0.id == r.id } ?? 0) * 2 >= d.rows.count
                RuleMark(x: .value("Selected", r.date)).foregroundStyle(t.label3)
                PointMark(x: .value("Selected", r.date), y: .value(metric.title, r.value))
                    .symbol { Circle().fill(color).frame(width: 9, height: 9).overlay(Circle().strokeBorder(t.card, lineWidth: 2)) }
                    .annotation(position: right ? .leading : .trailing, alignment: .center, spacing: 12,
                                overflowResolution: .init(x: .disabled, y: .fit(to: .chart))) { popover(r, d) }
            }
        }
        .chartXSelection(value: $hover)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                AxisGridLine().foregroundStyle(t.sep)
                AxisValueLabel {
                    if let x = v.as(Double.self) {
                        Text(metric.isRate ? String(format: "%.0f%%", x * 100) : x.formatted(.number.notation(.compactName).locale(Locale.current)))
                            .font(t.font(11)).foregroundStyle(t.label2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { v in
                AxisValueLabel {
                    if let x = v.as(Date.self) {
                        Text(x.formatted(.dateTime.month(.abbreviated).day()))
                            .font(t.font(11)).foregroundStyle(t.label2)
                    }
                }
            }
        }
    }

    private func popover(_ r: MetricData.Row, _ d: MetricData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(d.label(r.day, long: true)).font(t.font(11)).foregroundStyle(t.label2)
            popRow(String(localized: "This year"), MetricData.full(metric, r.value), t.label, bold: true)
            if lastYear, let ly = r.lastYear {
                popRow(String(localized: "Last year"), MetricData.full(metric, ly), t.label2)
                let c = Change(metric, value: r.value, previous: ly, arrows: false)
                popRow(String(localized: "Change"), c.text, c.color(t), bold: true)
            }
        }
        .padding(12)
        .frame(width: 184, alignment: .leading)
        .background(t.popover, in: RoundedRectangle(cornerRadius: t.rS + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.rS + 2, style: .continuous).strokeBorder(t.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    private func popRow(_ k: String, _ v: String, _ c: Color, bold: Bool = false) -> some View {
        HStack {
            Text(k).foregroundStyle(t.label2)
            Spacer()
            Text(v).foregroundStyle(c).fontWeight(bold ? .bold : .regular).monospacedDigit()
        }
        .font(t.font(13))
    }

    // MARK: Table

    private func table(_ d: MetricData) -> some View {
        let cols = d.columns(lastYear: lastYear)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(cols.indices, id: \.self) { i in
                    Text(i == 1 ? "\(cols[i]) ↓" : cols[i])
                        .font(t.font(12, .semibold)).foregroundStyle(i == 1 ? t.label : t.label2)
                        .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
                }
            }
            .lineLimit(1).padding(.horizontal, 16).frame(height: 36)
            .overlay(alignment: .bottom) { t.sep.frame(height: 1) }
            ForEach(Array(d.rows.reversed().enumerated()), id: \.element.id) { i, r in
                HStack(spacing: 12) {
                    ForEach(Array(d.cells(r, lastYear: lastYear).enumerated()), id: \.offset) { j, cell in
                        Text(cell.text)
                            .font(t.font(13, j == 1 ? .bold : .regular))
                            .foregroundStyle(cell.change.map { $0.color(t) } ?? (j == 2 ? t.label2 : t.label))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: j == 0 ? .leading : .trailing)
                    }
                }
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 16).frame(height: 32)
                .background(i % 2 == 1 ? t.fill2 : .clear)
            }
        }
        .themedCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: t.r, style: .continuous))
    }

    // MARK: Export

    private func export(_ d: MetricData) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(model.app?.name ?? "Vane") \(metric.title).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try d.csv(lastYear: lastYear).write(to: url, atomically: true, encoding: .utf8) } catch {
            NSAlert(error: error).runModal()
        }
        #endif
    }
}

/// Everything the metric screen shows, computed once per render.
struct MetricData {
    struct Row: Identifiable {
        let day: String, value: Double, lastYear: Double?
        var id: String { day }
        var date: Date { Day.date(day) }
    }

    let store: Store, app: String, metric: Metric, g: Granularity, territory: String
    var days: Int { Day.between(from, to) + 1 }
    let from: String, to: String, pFrom: String, pTo: String
    let value: Double, previous: Double, lastYearValue: Double
    let hasPrevious: Bool, hasLastYear: Bool
    let rows: [Row]
    let versions: [VersionMark]

    init(store: Store, app: String, metric: Metric, days: Int, territory: String) {
        self.store = store; self.app = app; self.metric = metric; self.territory = territory
        // Daily up to 90 days, weekly for a year (as the App Store sparklines).
        let g: Granularity = days > 90 ? .week : .day
        self.g = g
        let end = Self.anchor(store, app, metric)
        let start = Day.add(-(days - 1), to: end)
        from = start; to = end
        pTo = Day.add(-1, to: start)
        pFrom = Day.add(-Day.between(start, end), to: pTo)
        value = store.total(app, metric, territory: territory, from: start, to: end)
        previous = store.total(app, metric, territory: territory, from: pFrom, to: pTo)
        let covers: (String, String) -> Bool = { a, b in
            guard let first = store.series(app, metric, territory: territory, from: a, to: b).first?.day else { return false }
            return Day.between(a, first) <= 1
        }
        hasPrevious = covers(pFrom, pTo)
        hasLastYear = covers(Day.add(-364, to: start), Day.add(-364, to: end))
        lastYearValue = store.total(app, metric, territory: territory, from: Day.add(-364, to: start), to: Day.add(-364, to: end))
        let avg = metric.isGauge
        let cur = store.series(app, metric, territory: territory, from: start, to: end).bucketed(g, average: avg)
        let ly = Dictionary(uniqueKeysWithValues: store.series(app, metric, territory: territory, from: Day.add(-364, to: start), to: Day.add(-364, to: end))
            .bucketed(g, average: avg).map { ($0.day, $0.value) })
        var r = cur.map { Row(day: $0.day, value: $0.value, lastYear: ly[g.bucket(Day.add(-364, to: $0.day))]) }
        // Complete weeks only: a partial first or last week would read as a drop. The total above still covers every day.
        if g == .week {
            if Day.weekStart(start) != start, !r.isEmpty { r.removeFirst() }
            if Day.add(6, to: Day.weekStart(end)) != end, !r.isEmpty { r.removeLast() }
        }
        rows = r
        versions = store.versions(app).filter { $0.day >= start && $0.day <= end }
    }

    /// Where a metric's period ends: the same day the tile that opens it ends on.
    static func anchor(_ s: Store, _ app: String, _ m: Metric) -> String {
        let latest = s.lastDay(app) ?? Day.today()
        switch m {
        case .sessions, .crashes: return s.lastDay(app, .sessions) ?? latest
        case .activeSubs, .ratingsTotal, .newRatings, .sales, .proceeds: return s.lastDay(app, m) ?? latest
        default: return s.lastDay(app, .impressions) ?? s.lastDay(app, .firstDownloads) ?? latest
        }
    }

    var rangeName: String { String(localized: "Last \(periodNoun)") }
    var periodNoun: String { String(localized: "\(days) days") }
    var rangeLabel: String {
        let f: (String) -> String = { Day.date($0).formatted(days > 90 ? .dateTime.month(.abbreviated).day().year() : .dateTime.month(.abbreviated).day()) }
        return "\(f(from)) – \(f(to))"
    }

    func label(_ day: String, long: Bool = false) -> String {
        let d = Day.date(day)
        switch g {
        case .week: return String(localized: "Week of \(d.formatted(.dateTime.month(.abbreviated).day()))")
        case .month, .year: return d.formatted(.dateTime.month(.wide).year())
        case .day: return long ? d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) : d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    /// Full-precision value: 5,412 · 37.8% · €1,203.40.
    static func full(_ m: Metric, _ v: Double) -> String {
        m.isRate ? Num.pct(v) : (m == .proceeds || m == .sales) ? m.format(v) : Num.int(v)
    }

    /// App Store metrics get the funnel columns next to them.
    private var funnel: Bool { metric.isAppStore }

    func columns(lastYear: Bool) -> [String] {
        [String(localized: "Date"), metric == .firstDownloads ? String(localized: "Downloads") : metric.title] + (lastYear ? [String(localized: "Last year"), String(localized: "vs last year")] : []) + (funnel ? [String(localized: "Impressions"), String(localized: "Page views"), String(localized: "Conversion")] : [])
    }

    func cells(_ r: Row, lastYear: Bool) -> [(text: String, change: Change?)] {
        var out: [(String, Change?)] = [(label(r.day), nil), (Self.full(metric, r.value), nil)]
        if lastYear {
            out.append((r.lastYear.map { Self.full(metric, $0) } ?? "—", nil))
            if let ly = r.lastYear, ly > 0 {
                let c = Change(metric, value: r.value, previous: ly, arrows: false)
                out.append((c.text, c))
            } else { out.append(("—", nil)) }
        }
        if funnel {
            let e = end(of: r.day)
            // No analytics for this period (before Apple's first report): missing, not zero.
            if store.series(app, .impressions, territory: territory, from: r.day, to: e).isEmpty {
                out += [("—", nil), ("—", nil), ("—", nil)]
            } else {
                out.append((Num.k(store.total(app, .impressions, territory: territory, from: r.day, to: e)), nil))
                out.append((Num.int(store.total(app, .pageViews, territory: territory, from: r.day, to: e)), nil))
                out.append((Num.pct(store.total(app, .pageCR, territory: territory, from: r.day, to: e)), nil))
            }
        }
        return out.map { (text: $0.0, change: $0.1) }
    }

    private func end(of day: String) -> String {
        let e: String = switch g {
        case .week: Day.add(6, to: day)
        case .month, .year: Day.add(-1, to: Day.monthStart(Day.add(32, to: day)))
        case .day: day
        }
        return min(e, to)
    }

    func csv(lastYear: Bool) -> String {
        let esc: (String) -> String = { $0.contains(",") ? "\"\($0)\"" : $0 }
        let head = (["date"] + columns(lastYear: lastYear).dropFirst()).map(esc).joined(separator: ",")
        let body = rows.reversed().map { r in ([r.day] + cells(r, lastYear: lastYear).dropFirst().map(\.text)).map(esc).joined(separator: ",") }
        return ([head] + body).joined(separator: "\n") + "\n"
    }

    func chatContext(_ name: String) -> String {
        var s = "Screen: \(metric.title) for \(name), \(territory.isEmpty ? "all territories" : Territories.name(territory)), \(rangeName.lowercased()) (\(from) to \(to)), by \(g.rawValue.lowercased())\n"
        s += "Total \(Self.full(metric, value)), previous period \(Self.full(metric, previous)), same period last year \(Self.full(metric, lastYearValue))\n"
        s += rows.map { "\($0.day): \(Self.full(metric, $0.value))" + ($0.lastYear.map { " (last year \(Self.full(metric, $0)))" } ?? "") }.joined(separator: "\n")
        if !versions.isEmpty { s += "\nReleases: " + versions.map { "\($0.version) on \($0.day)" }.joined(separator: "; ") }
        return s
    }
}

private extension Metric {
    var isAppStore: Bool { AlmanacTheme.key(self) != nil || self == .ttr || self == .pageCR }
}
