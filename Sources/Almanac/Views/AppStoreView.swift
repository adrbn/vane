import AlmanacCore
import SwiftUI

/// App Store overview: bento grid (Ticker: watchlist + big chart). Falls back to "Data arriving" until Apple's first analytics report lands.
struct AppStoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @AppStorage("period") private var days = 28

    var body: some View {
        let app = model.appId ?? ""
        if model.store.lastDay(app, .impressions) == nil && model.store.lastDay(app, .firstDownloads) == nil {
            DataArrivingView()
        } else {
            let d = AppStoreData(store: model.store, app: app, days: days)
            Screen(title: String(localized: "App Store"), subtitle: "\(model.app?.name ?? "") · \(d.range)", inspector: true, scrolls: false) {
                GlassSegments(options: [(7, String(localized: "7 Days")), (28, String(localized: "28 Days")), (90, String(localized: "90 Days")), (365, String(localized: "Year"))], selection: $days)
            } content: {
                if t.usesRail {
                    VStack(alignment: .leading, spacing: 20) {
                        if d.pending { AnalyticsPending(compact: true) }
                        TickerOverview(d: d)
                    }
                } else { Bento(d: d) }
            }
            .onAppear { model.chatContext = d.chatContext(model.app?.name ?? "") }
        }
    }
}

/// Everything the overview shows, computed once per period.
struct AppStoreData {
    let store: Store, app: String, days: Int
    let from: String, to: String, pFrom: String, pTo: String
    /// Sales reports are in, Apple's analytics report isn't yet.
    let pending: Bool

    init(store: Store, app: String, days: Int) {
        self.store = store; self.app = app; self.days = days
        pending = store.lastDay(app, .impressions) == nil
        to = store.lastDay(app, .impressions) ?? store.lastDay(app, .firstDownloads) ?? Day.today()
        from = Day.add(-(days - 1), to: to)
        pTo = Day.add(-1, to: from)
        pFrom = Day.add(-(days - 1), to: pTo)
    }

    /// False for analytics metrics while the first report is pending: show "Expected", never a fake 0.
    func has(_ m: Metric) -> Bool { !pending || [.firstDownloads, .redownloads, .downloads, .sales, .proceeds].contains(m) }
    func value(_ m: Metric) -> Double { store.total(app, m, from: from, to: to) }
    func previous(_ m: Metric) -> Double { store.total(app, m, from: pFrom, to: pTo) }
    func change(_ m: Metric, arrows: Bool = true) -> Change {
        has(m) && hasPrevious(m) ? Change(m, value: value(m), previous: previous(m), arrows: arrows) : .noHistory
    }
    /// History reaches back to the start of the previous period.
    func hasPrevious(_ m: Metric) -> Bool {
        guard let first = store.series(app, m, from: pFrom, to: pTo).first?.day else { return false }
        return Day.between(pFrom, first) <= 1
    }
    /// Daily, or weekly sums past 90 days.
    func spark(_ m: Metric) -> [Double] { points(m).map(\.value) }
    /// Daily, or weekly past 90 days with complete weeks only: a partial first or last week would read as a drop.
    func points(_ m: Metric) -> [Point] {
        let p = store.series(app, m, from: from, to: to)
        guard days > 90 else { return p }
        var w = p.bucketed(.week, average: m.isGauge)
        if Day.weekStart(from) != from, !w.isEmpty { w.removeFirst() }
        if Day.add(6, to: Day.weekStart(to)) != to, !w.isEmpty { w.removeLast() }
        return w
    }
    var daily: [Point] { store.series(app, .firstDownloads, from: from, to: to) }
    var best: Point? { daily.max { $0.value < $1.value } }

    var range: String {
        guard days == 365 else { return "\(Self.md(from)) – \(Self.md(to))" }
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day().year().locale(Locale.current)
        return "\(Day.date(from).formatted(f)) – \(Day.date(to).formatted(f))"
    }
    var per: String { days == 365 ? String(localized: "year") : String(localized: "\(days) days") }
    static func md(_ d: String) -> String { Day.date(d).formatted(.dateTime.month(.abbreviated).day()) }

    func shown(_ m: Metric) -> String { has(m) ? Num.value(m, value(m)) : "—" }
    func was(_ m: Metric) -> String { !has(m) ? AnalyticsPending.expected : hasPrevious(m) ? String(localized: "was \(Num.value(m, previous(m)))") : "" }

    func chatContext(_ name: String) -> String {
        "Screen: App Store overview for \(name), \(from) to \(to) vs \(pFrom) to \(pTo)\n" +
            [Metric.impressions, .pageViews, .ttr, .firstDownloads, .redownloads, .pageCR].map {
                "- \($0.title): \(Num.value($0, value($0))) (previous: \(Num.value($0, previous($0))))"
            }.joined(separator: "\n")
    }
}

// MARK: - Bento (Color Blocks, Nocturne, Candy Glass)

private struct Bento: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let d: AppStoreData

    var body: some View {
        GeometryReader { g in
            let col = (g.size.width - 36) / 4
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Hero(d: d).frame(width: col * 2 + 12)
                    VStack(spacing: 12) {
                        HStack(spacing: 12) { MetricCard(d: d, metric: .impressions); MetricCard(d: d, metric: .pageViews) }
                        HStack(spacing: 12) { MetricCard(d: d, metric: .ttr); MetricCard(d: d, metric: .redownloads) }
                    }
                }
                .frame(minHeight: 436, maxHeight: .infinity)
                HStack(alignment: .top, spacing: 12) {
                    MetricCard(d: d, metric: .pageCR, caption: String(localized: "Viewers who downloaded")).frame(width: col)
                    if d.pending { AnalyticsPending(compact: false).frame(maxHeight: .infinity) } else { FunnelCard(d: d) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Hero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let d: AppStoreData

    var body: some View {
        let c = d.change(.firstDownloads, arrows: false)
        let shape = RoundedRectangle(cornerRadius: t.r, style: .continuous)
        Button { model.section = .metric(.firstDownloads) } label: {
            ZStack(alignment: .topLeading) {
                GeometryReader { g in
                    chart.frame(height: max(168, g.size.height - 248)).frame(maxHeight: .infinity, alignment: .bottom)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("First-time downloads, last \(d.per)").font(t.font(15, .semibold)).foregroundStyle(t.heroFg2)
                    Text.tracked(Num.int(d.value(.firstDownloads)), t.heroTracking).font(t.heroFont).monospacedDigit()
                        .foregroundStyle(t.heroFg).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 10).padding(.leading, -4)
                    (Text(c.text).foregroundStyle(t.heroBackground == nil ? c.color(t) : t.heroFg).fontWeight(.bold)
                        + Text(c.text == Change.noHistory.text ? "" : String(localized: " on the previous \(d.per)")).foregroundStyle(t.heroFg2).fontWeight(.medium))
                        .font(t.font(17)).monospacedDigit().padding(.top, 10)
                    if let b = d.best, b.value > 0 {
                        Text("Best day: \(Num.int(b.value)) on \(AppStoreData.md(b.day))").font(t.font(13)).foregroundStyle(t.heroFg2).monospacedDigit().padding(.top, 2)
                    }
                }
                .padding(t.heroBackground == nil ? 0 : t.heroPad)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { if let bg = t.heroBackground { shape.fill(bg) } }
            .clipShape(t.heroBackground == nil ? AnyShape(Rectangle()) : AnyShape(shape))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var chart: some View {
        let v = d.spark(.firstDownloads)
        let area = LinePath(values: v, floorZero: true, closed: true)
        let line = LinePath(values: v, floorZero: true)
        let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        switch t.id {
        case "nocturne":
            ZStack {
                area.fill(LinearGradient(colors: [Color(css: "#FF5FA2").opacity(0.28), Color(css: "#7A5CFF").opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(LinearGradient(colors: [Color(css: "#7A5CFF"), Color(css: "#FF5FA2"), Color(css: "#FFB547")], startPoint: .leading, endPoint: .trailing), style: style)
            }
        default:
            ZStack {
                area.fill(Color.white.opacity(0.16))
                line.stroke(t.heroFg, style: style)
            }
        }
    }
}

/// Tile: card + colored icon square, or a solid fill (Color Blocks). Sparkline takes the extra height.
struct MetricCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let d: AppStoreData
    let metric: Metric
    var caption: String? = nil

    var body: some View {
        let c = d.change(metric)
        let fl = t.tileFill(metric)
        let fg2 = fl?.fg2 ?? t.label2
        Button { model.section = .metric(metric) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if fl == nil { IconSquare(symbol: Self.symbol(metric), style: t.square(metric), size: 26) }
                    Text(Self.label(metric)).font(t.font(14, .semibold)).foregroundStyle(fg2).lineLimit(1)
                }
                if let caption { Text(caption).font(t.font(13)).foregroundStyle(fg2).padding(.top, 6) }
                Text.tracked(d.shown(metric), -0.9).font(t.numFont).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 14)
                (Text(d.has(metric) ? c.text : "").foregroundStyle(fl?.fg ?? c.color(t)).fontWeight(.bold) + Text((d.has(metric) ? " " : "") + d.was(metric)).foregroundStyle(fg2))
                    .font(t.font(13)).monospacedDigit().lineLimit(1).padding(.top, 4)
                Spark(values: d.spark(metric), color: fl?.fg ?? t.color(metric, up: c.up))
                    .frame(minHeight: 30, maxHeight: 72).padding(.top, 12).opacity(d.has(metric) ? 1 : 0)
            }
            .foregroundStyle(fl?.fg ?? t.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .themedCard(fill: fl?.bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func label(_ m: Metric) -> String { m == .pageViews ? String(localized: "Page views") : m == .pageCR ? String(localized: "Conversion rate") : m.title }
    static func symbol(_ m: Metric) -> String {
        switch m {
        case .impressions: "eye.fill"
        case .pageViews: "doc.richtext.fill"
        case .ttr: "hand.tap.fill"
        case .firstDownloads, .downloads: "arrow.down.circle.fill"
        case .redownloads: "arrow.clockwise"
        case .pageCR: "target"
        default: "chart.xyaxis.line"
        }
    }
}

private struct FunnelCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let d: AppStoreData

    var body: some View {
        let imp = d.value(.impressions), pv = d.value(.pageViews), dl = d.value(.downloads)
        let ttr = d.change(.ttr), conv = d.change(.pageCR)
        VStack(alignment: .leading, spacing: 0) {
            Text("From seen to downloaded").font(t.font(17, .bold))
            Text("Of every 1,000 people who saw \(model.app?.name ?? "your app"), \(per1000(pv, imp)) opened its page and \(Num.int(d.value(.pageCR) * 1000)) downloaded it.")
                .font(t.font(13)).foregroundStyle(t.label2).monospacedDigit().padding(.top, 4)
            HStack(alignment: .top, spacing: 24) {
                stage(Num.k(imp), Text("saw it in the App Store"), share: 1, color: color(.impressions))
                stage(Num.k(pv), Text("opened the page · ") + Text(Num.pct(d.value(.ttr))).foregroundStyle(ttr.color(t)).fontWeight(.bold), share: imp > 0 ? pv / imp : 0, color: color(.pageViews))
                stage(Num.int(dl), Text("downloaded · ") + Text(Num.pct(d.value(.pageCR))).foregroundStyle(conv.color(t)).fontWeight(.bold), share: d.value(.pageCR), color: color(.firstDownloads))
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .themedCard()
    }

    private func color(_ m: Metric) -> Color { t.colorByDirection ? (m == .firstDownloads ? t.pos : t.label) : t.color(m) }
    private func per1000(_ a: Double, _ b: Double) -> String { b > 0 ? Num.int(a / b * 1000) : "0" }

    private func stage(_ value: String, _ caption: Text, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text.tracked(value, -1).font(t.font(36, t.numWeight)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            caption.font(t.font(13)).foregroundStyle(t.label2).monospacedDigit().lineLimit(1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.fill)
                    Capsule().fill(color).frame(width: max(12, g.size.width * share))
                }
            }
            .frame(height: 12).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ticker: watchlist + full-height chart

private struct TickerOverview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let d: AppStoreData
    @State private var selected: Metric = .firstDownloads

    private let rows: [Metric] = [.firstDownloads, .impressions, .pageViews, .ttr, .redownloads, .pageCR]

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Last \(d.per) · \(d.range)").font(t.font(13)).foregroundStyle(t.label2).padding(.horizontal, 14).padding(.bottom, 8)
                ForEach(rows) { row($0) }
            }
            .frame(width: 400)
            .frame(maxHeight: .infinity, alignment: .top)
            chart
        }
    }

    private func row(_ m: Metric) -> some View {
        let c = d.change(m, arrows: false)
        let on = m == selected
        return Button { if on { model.section = .metric(m) } else { selected = m } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(MetricCard.label(m)).font(t.font(15, .semibold)).lineLimit(1)
                    Text(d.was(m)).font(t.font(12)).foregroundStyle(t.label2).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spark(values: d.spark(m), color: c.flat ? t.label2 : t.color(m, up: c.up), width: 1.5).frame(width: 72, height: 28).opacity(d.has(m) ? 1 : 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(d.shown(m)).font(t.font(16, .semibold)).monospacedDigit().foregroundStyle(d.has(m) ? t.label : t.label3)
                    Text(c.text == Change.noHistory.text ? "—" : c.flat ? (m.isRate ? String(localized: "0.0 pts") : "0.0%") : c.text).font(t.font(13, .bold)).monospacedDigit()
                        .foregroundStyle(.black).padding(.horizontal, 8).frame(minWidth: 72, alignment: .trailing).frame(height: 24)
                        .background(c.flat ? Color(css: "#8E8E93") : c.up ? t.pos : t.neg, in: RoundedRectangle(cornerRadius: 6))
                        .opacity(d.has(m) && c.text != Change.noHistory.text ? 1 : 0)
                }
                .frame(width: 92, alignment: .trailing)
            }
            .padding(.horizontal, 14).frame(minHeight: 72, maxHeight: 128)
            .background(on ? t.fill : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottom) { if !on { t.sep.frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chart: some View {
        let m = selected
        let c = d.change(m, arrows: false)
        let pts = store(m)
        let peak = pts.max { $0.value < $1.value }
        return VStack(alignment: .leading, spacing: 0) {
            Text(MetricCard.label(m)).font(t.font(17)).foregroundStyle(t.label2)
            Text.tracked(d.shown(m), t.heroTracking).font(t.heroFont).monospacedDigit().lineLimit(1).frame(height: 84)
            (Text(d.has(m) ? c.text : AnalyticsPending.expected).foregroundStyle(d.has(m) ? c.color(t) : t.label2) + Text(c.text == Change.noHistory.text ? "" : String(localized: " on the previous \(d.per)")).foregroundStyle(t.label2).fontWeight(.regular))
                .font(t.font(17, .semibold)).monospacedDigit()
            GeometryReader { g in
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) { Spacer(); t.sep.frame(height: 1); Spacer(); t.sep.frame(height: 1); Spacer() }
                    LinePath(values: pts.map(\.value), floorZero: !m.isRate, closed: true).fill(t.pos.opacity(0.14))
                    LinePath(values: pts.map(\.value), floorZero: !m.isRate).stroke(t.pos, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    if let peak {
                        Text("\(Num.value(m, peak.value)) on \(AppStoreData.md(peak.day))").font(t.font(12, .semibold)).monospacedDigit()
                            .padding(.trailing, 12).offset(y: g.size.height * 0.18)
                    }
                }
            }
            .overlay(alignment: .bottom) { t.sep.frame(height: 1) }
            .overlay { if !d.has(m) { Text("\(MetricCard.label(m)) arrive with Apple's first analytics report").font(t.font(13)).foregroundStyle(t.label2) } }
            .padding(.top, 24)
            HStack {
                ForEach(axisLabels(pts), id: \.self) { Text($0); if $0 != axisLabels(pts).last { Spacer() } }
            }
            .font(t.font(11)).foregroundStyle(t.label2).padding(.top, 8)
            stats(pts, peak).padding(.top, 20)
        }
    }

    private func store(_ m: Metric) -> [Point] {
        d.points(m)
    }

    private func axisLabels(_ p: [Point]) -> [String] {
        guard p.count > 1 else { return [] }
        return (0..<5).map { p[min(p.count - 1, $0 * (p.count - 1) / 4)].day }.map(AppStoreData.md)
    }

    private func stats(_ p: [Point], _ peak: Point?) -> some View {
        let search = d.value(.searchImpressions), imp = d.value(.impressions)
        let releases = model.store.versions(d.app).filter { $0.day >= d.from && $0.day <= d.to }.map(\.version)
        let cells: [(String, String)] = [
            (String(localized: "Best day"), peak.map { "\(Num.value(selected, $0.value)) · \(AppStoreData.md($0.day))" } ?? "—"),
            (String(localized: "Daily average"), selected.isRate ? Num.pct(d.value(selected)) : Num.int(d.value(selected) / Double(max(1, d.store.series(d.app, selected, from: d.from, to: d.to).count)))),
            (String(localized: "From App Store search"), d.pending ? "—" : imp > 0 ? Num.pct(search / imp).replacingOccurrences(of: ".0%", with: "%") : "—"),
            (String(localized: "Tap-through"), d.shown(.ttr)),
            (String(localized: "Conversion"), d.shown(.pageCR)),
            (String(localized: "Releases"), releases.isEmpty ? String(localized: "None") : releases.suffix(2).joined(separator: " · ")),
        ]
        return Grid(horizontalSpacing: 24, verticalSpacing: 0) {
            ForEach(0..<2) { r in
                GridRow {
                    ForEach(0..<3) { c in
                        let cell = cells[r * 3 + c]
                        HStack(spacing: 8) {
                            Text(cell.0).foregroundStyle(t.label2).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(cell.1).fontWeight(.semibold).monospacedDigit().lineLimit(1)
                        }
                        .frame(height: 40)
                        .overlay(alignment: .top) { t.sep.frame(height: 1) }
                    }
                }
            }
        }
        .font(t.font(13))
    }
}
