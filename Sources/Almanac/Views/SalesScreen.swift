#if os(macOS)
import AlmanacCore
import Charts
import SwiftUI

/// Sales: downloads and money by day, week, month or year from Apple's sales reports.
/// Releases are marked on the chart and get their own column, so every row has the same height.
struct SalesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @AppStorage("sales.granularity") private var g: Granularity = .week

    struct Row: Identifiable {
        var start: String, first: Double, re: Double, proceeds: Double, sales: Double, subs: Double, releases: [String], partial: Bool
        var id: String { start }
        var total: Double { first + re }
    }

    var body: some View {
        let app = model.appId ?? ""
        let rows = makeRows(app)
        let paid = rows.contains { $0.sales > 0 }, subs = rows.contains { $0.subs > 0 }
        Screen(title: String(localized: "Sales"), subtitle: "\(model.app?.name ?? "") · \(String(localized: "From Apple's daily sales reports"))", inspector: true, scrolls: false) {
            GlassSegments(options: [(Granularity.day, String(localized: "Daily")), (.week, String(localized: "Weekly")), (.month, String(localized: "Monthly")), (.year, String(localized: "Yearly"))], selection: $g)
        } content: {
            if rows.isEmpty {
                AnalyticsPending(compact: false).frame(height: 200)
            } else {
                VStack(spacing: 16) {
                    // The chart takes the spare height; the table is only as tall as its rows.
                    let complete = rows.filter { !$0.partial }
                    summary(complete.isEmpty ? rows : complete, complete: !complete.isEmpty, paid: paid)
                        .frame(minHeight: 280, maxHeight: .infinity)
                    table(rows, paid: paid, subs: subs)
                        .frame(maxHeight: 37 + 40 * CGFloat(rows.count))
                }
            }
        }
        .onAppear {
            model.chatContext = "Screen: Sales by \(g.rawValue.lowercased()) for \(model.app?.name ?? "") (USD)\n"
                + rows.prefix(60).map { "\($0.start): first-time downloads \(Int($0.first)), redownloads \(Int($0.re)), proceeds \(Metric.proceeds.format($0.proceeds)), sales \(Metric.sales.format($0.sales))\($0.releases.isEmpty ? "" : ", release " + $0.releases.joined(separator: ", "))" }
                    .joined(separator: "\n")
        }
    }

    // MARK: Data

    private func makeRows(_ app: String) -> [Row] {
        guard let last = model.store.lastDay(app, .firstDownloads),
              let first = model.store.series(app, .firstDownloads, from: "2000-01-01", to: last).first?.day else { return [] }
        let span: Int = switch g { case .day: 59; case .week: 7 * 52; case .month: 730; case .year: 1825 }
        let from = max(first, g.bucket(Day.add(-span, to: last)))
        func by(_ m: Metric) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: model.store.series(app, m, from: from, to: last).bucketed(g).map { ($0.day, $0.value) })
        }
        let f = by(.firstDownloads), r = by(.redownloads), p = by(.proceeds), s = by(.sales)
        var subs: [String: Double] = [:]
        for pt in model.store.series(app, .activeSubs, from: from, to: last) { subs[g.bucket(pt.day)] = pt.value }
        let versions = model.store.marks(app)
        let current = g.bucket(last)
        let open = g != .day && g.bucket(Day.add(1, to: last)) == current
        return Set(f.keys).union(r.keys).sorted(by: >).map { b in
            Row(start: b, first: f[b] ?? 0, re: r[b] ?? 0, proceeds: p[b] ?? 0, sales: s[b] ?? 0, subs: subs[b] ?? 0,
                releases: versions.filter { g.bucket($0.day) == b }.map(\.version), partial: (b == current && open) || (b == g.bucket(first) && b != first))
        }
    }

    private func label(_ day: String, short: Bool = false) -> String {
        let d = Day.date(day)
        switch g {
        case .day: return d.formatted(short ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            let e = Day.date(Day.add(6, to: day))
            return short ? d.formatted(.dateTime.month(.abbreviated).day()) : "\(d.formatted(.dateTime.month(.abbreviated).day())) – \(e.formatted(.dateTime.month(.abbreviated).day()))"
        case .month: return d.formatted(short ? .dateTime.month(.abbreviated) : .dateTime.month(.wide).year())
        case .year: return d.formatted(.dateTime.year())
        }
    }

    private var unit: String { g.title.lowercased() }

    // MARK: Summary card

    private func summary(_ rows: [Row], complete: Bool, paid: Bool) -> some View {
        let total = rows.reduce(0) { $0 + $1.total }
        let best = rows.max { $0.total < $1.total }
        let proceeds = rows.reduce(0) { $0 + $1.proceeds }
        let ordered = rows.sorted { $0.start < $1.start }
        return HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 18) {
                stat(String(localized: "Downloads"), Num.int(total), String(localized: "\(Num.int(rows.reduce(0) { $0 + $1.first })) first-time · \(Num.int(rows.reduce(0) { $0 + $1.re })) re"), big: true)
                stat(paid ? String(localized: "Sales") : String(localized: "Proceeds"), paid ? Metric.sales.format(rows.reduce(0) { $0 + $1.sales }) : Metric.proceeds.format(proceeds),
                     paid ? String(localized: "\(Metric.proceeds.format(proceeds)) after Apple's commission") : String(localized: "Free app, no in-app purchases sold"))
                if let best, rows.count > 1 { stat(String(localized: "Best \(unit)"), Num.int(best.total), label(best.start)) }
                Spacer(minLength: 0)
                Text(verbatim: "\(periodsText(ordered.count, complete: complete)) · \(ordered.count == 1 ? label(ordered[0].start, short: true) : "\(label(ordered.first!.start, short: true)) – \(label(ordered.last!.start, short: true))")")
                    .font(t.font(11)).foregroundStyle(t.label2).lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)
            chart(ordered)
        }
        .themedCard()
    }

    private func periodsText(_ n: Int, complete: Bool) -> String {
        switch g {
        case .day: complete ? String(localized: "\(n) complete days") : String(localized: "\(n) days, partly covered")
        case .week: complete ? String(localized: "\(n) complete weeks") : String(localized: "\(n) weeks, partly covered")
        case .month: complete ? String(localized: "\(n) complete months") : String(localized: "\(n) months, partly covered")
        case .year: complete ? String(localized: "\(n) complete years") : String(localized: "\(n) years, partly covered")
        }
    }

    private func stat(_ label: String, _ value: String, _ caption: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(t.font(13, .semibold)).foregroundStyle(t.label2)
            Text.tracked(value, big ? -0.9 : -0.4).font(big ? t.numFont : t.font(22, t.numWeight)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(t.font(12)).foregroundStyle(t.label2).monospacedDigit().lineLimit(1)
        }
    }

    private func chart(_ rows: [Row]) -> some View {
        let few = rows.count <= 16
        let firstTime = String(localized: "First-time"), redownloads = String(localized: "Redownloads")
        return Chart {
            ForEach(rows) { r in
                BarMark(x: .value("Period", r.start), y: .value("Downloads", r.first), width: barWidth(rows.count))
                    .foregroundStyle(by: .value("Kind", firstTime))
                BarMark(x: .value("Period", r.start), y: .value("Downloads", r.re), width: barWidth(rows.count))
                    .foregroundStyle(by: .value("Kind", redownloads))
                    .annotation(position: .top, spacing: 4) {
                        // Release chips sit on their bar, like the Release column below.
                        if let v = r.releases.last {
                            Text(v).font(t.font(10, .bold)).foregroundStyle(t.accentText)
                                .padding(.horizontal, 6).frame(height: 18).background(t.accentSoft, in: Capsule())
                        }
                    }
            }
        }
        .chartForegroundStyleScale([firstTime: t.color(.firstDownloads), redownloads: t.color(.firstDownloads).opacity(0.4)])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis {
            // One category per period, so every label sits under its bar.
            AxisMarks(values: few ? rows.map(\.start) : rows.enumerated().filter { $0.offset % max(1, rows.count / 6) == 0 }.map(\.element.start)) { v in
                AxisValueLabel { if let d = v.as(String.self) { Text(label(d, short: true)).font(t.font(11)).foregroundStyle(t.label2) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(t.sep)
                AxisValueLabel { if let n = v.as(Double.self) { Text(Num.k(n)).font(t.font(11)).foregroundStyle(t.label2) } }
            }
        }
    }

    /// A handful of periods would otherwise draw slabs; keep bars at a readable width.
    private func barWidth(_ n: Int) -> MarkDimension { n <= 6 ? .fixed(56) : .ratio(0.7) }


    // MARK: Table

    private struct Column {
        let title: String; let width: CGFloat?
        /// `title` doubles as the column's identifier, so only the shown text is localized.
        var label: String {
            switch title {
            case "First-time": String(localized: "First-time")
            case "Redownloads": String(localized: "Redownloads")
            case "Total": String(localized: "Total")
            case "Sales": String(localized: "Sales")
            case "Proceeds": String(localized: "Proceeds")
            case "Active subs": String(localized: "Active subs")
            case "Release": String(localized: "Release")
            default: title
            }
        }
    }

    private func columns(paid: Bool, subs: Bool) -> [Column] {
        [Column(title: g.title, width: nil), Column(title: "First-time", width: 110), Column(title: "Redownloads", width: 110),
         Column(title: "Total", width: 160)]
            + (paid ? [Column(title: "Sales", width: 110)] : []) + [Column(title: "Proceeds", width: 110)]
            + (subs ? [Column(title: "Active subs", width: 110)] : []) + [Column(title: "Release", width: 120)]
    }

    private func table(_ rows: [Row], paid: Bool, subs: Bool) -> some View {
        let cols = columns(paid: paid, subs: subs)
        let peak = max(1, rows.map(\.total).max() ?? 1)
        return VStack(spacing: 0) {
            line(cols, header: true) { i in Text(cols[i].label) }
                .font(t.font(12, .semibold)).foregroundStyle(t.label2)
                .overlay(alignment: .bottom) { t.sep.frame(height: 1) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { r in
                        line(cols, header: false) { i in cell(cols[i].title, r, peak) }
                            .font(t.font(13)).monospacedDigit()
                            .overlay(alignment: .bottom) { t.sep.frame(height: 1).opacity(0.6) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .themedCard(padding: 0)
    }

    private func line<C: View>(_ cols: [Column], header: Bool, @ViewBuilder _ cell: @escaping (Int) -> C) -> some View {
        HStack(spacing: 16) {
            ForEach(cols.indices, id: \.self) { i in
                let c = cols[i]
                // Fixed columns give up to 40% when the window is narrow; the same range on every row keeps them aligned.
                cell(i).lineLimit(1)
                    .frame(minWidth: c.width.map { $0 * 0.6 } ?? 64, maxWidth: c.width ?? .infinity,
                           alignment: i == 0 || c.title == "Release" || c.title == "Total" ? .leading : .trailing)
            }
        }
        .padding(.horizontal, 20).frame(height: header ? 36 : 40)
    }

    @ViewBuilder private func cell(_ col: String, _ r: Row, _ peak: Double) -> some View {
        switch col {
        case "First-time": Text(Num.int(r.first))
        case "Redownloads": Text(Num.int(r.re)).foregroundStyle(t.label2)
        case "Total":
            HStack(spacing: 10) {
                Text(Num.int(r.total)).fontWeight(.semibold).frame(width: 56, alignment: .trailing)
                GeometryReader { geo in
                    Capsule().fill(t.color(.firstDownloads).opacity(r.partial ? 0.35 : 0.85))
                        .frame(width: max(3, geo.size.width * r.total / peak), height: 6).frame(maxHeight: .infinity)
                }
            }
        case "Sales": Text(Metric.sales.format(r.sales))
        case "Proceeds": Text(Metric.proceeds.format(r.proceeds)).foregroundStyle(r.proceeds > 0 ? t.label : t.label3)
        case "Active subs": Text(r.subs > 0 ? Num.int(r.subs) : "—").foregroundStyle(r.subs > 0 ? t.label : t.label3)
        case "Release":
            HStack(spacing: 4) {
                ForEach(r.releases.suffix(2), id: \.self) { v in
                    Text(v).font(t.font(11, .bold)).foregroundStyle(t.accentText)
                        .padding(.horizontal, 7).frame(height: 20).background(t.accentSoft, in: Capsule())
                }
            }
        default:
            HStack(spacing: 8) {
                Text(label(r.start)).fontWeight(.medium).lineLimit(1)
                if r.partial {
                    Text("Partial").font(t.font(11, .semibold)).foregroundStyle(t.label2)
                        .padding(.horizontal, 7).frame(height: 20).background(t.fill, in: Capsule())
                        .help("This \(unit) isn't fully covered by the sales reports yet")
                }
            }
        }
    }
}
#endif
