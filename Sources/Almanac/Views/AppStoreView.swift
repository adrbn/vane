import AlmanacCore
import SwiftUI

/// App Store overview: bento grid (Ticker: watchlist + big chart). Falls back to "Data arriving" until Apple's first analytics report lands.
struct AppStoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @AppStorage("period") private var days = 28

    var body: some View {
        let app = model.appId ?? ""
        if model.store.lastDay(app, .impressions) == nil {
            DataArrivingView()
        } else {
            let d = AppStoreData(store: model.store, app: app, days: days)
            Screen(title: "App Store", subtitle: "\(model.app?.name ?? "") · \(d.range)", inspector: true, scrolls: false) {
                GlassSegments(options: [(7, "7 Days"), (28, "28 Days"), (90, "90 Days"), (365, "Year")], selection: $days)
            } content: {
                if t.usesRail { TickerOverview(d: d) } else { Bento(d: d) }
            }
            .onAppear { model.chatContext = d.chatContext(model.app?.name ?? "") }
        }
    }
}

/// Everything the overview shows, computed once per period.
struct AppStoreData {
    let store: Store, app: String, days: Int
    let from: String, to: String, pFrom: String, pTo: String

    init(store: Store, app: String, days: Int) {
        self.store = store; self.app = app; self.days = days
        to = store.lastDay(app, .impressions) ?? Day.today()
        from = Day.add(-(days - 1), to: to)
        pTo = Day.add(-1, to: from)
        pFrom = Day.add(-(days - 1), to: pTo)
    }

    func value(_ m: Metric) -> Double { store.total(app, m, from: from, to: to) }
    func previous(_ m: Metric) -> Double { store.total(app, m, from: pFrom, to: pTo) }
    func change(_ m: Metric, arrows: Bool = true) -> Change { Change(m, value: value(m), previous: previous(m), arrows: arrows) }
    /// Daily, or weekly sums past 90 days.
    func spark(_ m: Metric) -> [Double] {
        let p = store.series(app, m, from: from, to: to)
        return (days > 90 ? p.bucketed(.week) : p).map(\.value)
    }
    var daily: [Point] { store.series(app, .firstDownloads, from: from, to: to) }
    var best: Point? { daily.max { $0.value < $1.value } }

    var range: String { "\(Self.md(from)) – \(Self.md(to))" }
    var per: String { days == 365 ? "year" : "\(days) days" }
    static func md(_ d: String) -> String { Day.date(d).formatted(.dateTime.month(.abbreviated).day()) }

    func was(_ m: Metric) -> String { "was " + Num.value(m, previous(m)) }

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
                    MetricCard(d: d, metric: .pageCR, caption: "Page visitors who downloaded").frame(width: col)
                    FunnelCard(d: d)
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
                    Text(Num.int(d.value(.firstDownloads))).font(t.heroFont).tracking(t.heroTracking).monospacedDigit()
                        .foregroundStyle(t.heroFg).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 10).padding(.leading, -4)
                    (Text(c.text).foregroundStyle(t.heroBackground == nil ? c.color(t) : t.heroFg).fontWeight(.bold)
                        + Text(" on the previous \(d.per)").foregroundStyle(t.heroFg2).fontWeight(.medium))
                        .font(t.font(17)).monospacedDigit().padding(.top, 10)
                    if let b = d.best {
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
        let v = d.days > 90 ? d.daily.bucketed(.week).map(\.value) : d.daily.map(\.value)
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
                Text(Num.value(metric, d.value(metric))).font(t.numFont).tracking(-0.9).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 14)
                (Text(c.text).foregroundStyle(fl?.fg ?? c.color(t)).fontWeight(.bold) + Text(" " + d.was(metric)).foregroundStyle(fg2))
                    .font(t.font(13)).monospacedDigit().lineLimit(1).padding(.top, 4)
                Spark(values: d.spark(metric), color: fl?.fg ?? t.color(metric, up: c.up))
                    .frame(minHeight: 30, maxHeight: 72).padding(.top, 12)
            }
            .foregroundStyle(fl?.fg ?? t.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .themedCard(fill: fl?.bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func label(_ m: Metric) -> String { m == .pageViews ? "Page views" : m == .pageCR ? "Conversion rate" : m.title }
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
        let imp = d.value(.impressions), pv = d.value(.pageViews), dl = d.value(.firstDownloads)
        let ttr = d.change(.ttr), conv = d.change(.pageCR)
        VStack(alignment: .leading, spacing: 0) {
            Text("From seen to downloaded").font(t.font(17, .bold))
            Text("Of every 1,000 people who saw \(model.app?.name ?? "your app"), \(per1000(pv, imp)) opened its page and \(per1000(dl, imp)) downloaded it.")
                .font(t.font(13)).foregroundStyle(t.label2).monospacedDigit().padding(.top, 4)
            HStack(alignment: .top, spacing: 24) {
                stage(Num.k(imp), Text("saw it in the App Store"), share: 1, color: color(.impressions))
                stage(Num.k(pv), Text("opened the page · ") + Text(Num.pct(d.value(.ttr))).foregroundStyle(ttr.color(t)).fontWeight(.bold), share: imp > 0 ? pv / imp : 0, color: color(.pageViews))
                stage(Num.int(dl), Text("downloaded · ") + Text(Num.pct(d.value(.pageCR))).foregroundStyle(conv.color(t)).fontWeight(.bold), share: imp > 0 ? dl / imp : 0, color: color(.firstDownloads))
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
            Text(value).font(t.font(36, t.numWeight)).tracking(-1).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
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
                Spacer(minLength: 0)
            }
            .frame(width: 400)
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
                Spark(values: d.spark(m), color: c.flat ? t.label2 : t.color(m, up: c.up), width: 1.5).frame(width: 72, height: 28)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Num.value(m, d.value(m))).font(t.font(16, .semibold)).monospacedDigit()
                    Text(c.flat ? (m.isRate ? "0.0 pts" : "0.0%") : c.text).font(t.font(13, .bold)).monospacedDigit()
                        .foregroundStyle(.black).padding(.horizontal, 8).frame(minWidth: 72, alignment: .trailing).frame(height: 24)
                        .background(c.flat ? Color(css: "#8E8E93") : c.up ? t.pos : t.neg, in: RoundedRectangle(cornerRadius: 6))
                }
                .frame(width: 92, alignment: .trailing)
            }
            .padding(.horizontal, 14).frame(height: 72)
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
            Text(Num.value(m, d.value(m))).font(t.heroFont).tracking(t.heroTracking).monospacedDigit().lineLimit(1).frame(height: 84)
            (Text(c.text).foregroundStyle(c.color(t)) + Text(" on the previous \(d.per)").foregroundStyle(t.label2).fontWeight(.regular))
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
            .padding(.top, 24)
            HStack {
                ForEach(axisLabels(pts), id: \.self) { Text($0); if $0 != axisLabels(pts).last { Spacer() } }
            }
            .font(t.font(11)).foregroundStyle(t.label2).padding(.top, 8)
            stats(pts, peak).padding(.top, 20)
        }
    }

    private func store(_ m: Metric) -> [Point] {
        let p = model.store.series(d.app, m, from: d.from, to: d.to)
        return d.days > 90 ? p.bucketed(.week) : p
    }

    private func axisLabels(_ p: [Point]) -> [String] {
        guard p.count > 1 else { return [] }
        return (0..<5).map { p[min(p.count - 1, $0 * (p.count - 1) / 4)].day }.map(AppStoreData.md)
    }

    private func stats(_ p: [Point], _ peak: Point?) -> some View {
        let search = d.value(.searchImpressions), imp = d.value(.impressions)
        let releases = model.store.versions(d.app).filter { $0.day >= d.from && $0.day <= d.to }.map(\.version)
        let cells: [(String, String)] = [
            ("Best day", peak.map { "\(Num.value(selected, $0.value)) · \(AppStoreData.md($0.day))" } ?? "—"),
            ("Daily average", selected.isRate ? Num.pct(d.value(selected)) : Num.int(d.value(selected) / Double(max(1, Day.between(d.from, d.to) + 1)))),
            ("From App Store search", imp > 0 ? Num.pct(search / imp).replacingOccurrences(of: ".0%", with: "%") : "—"),
            ("Tap-through", Num.pct(d.value(.ttr))),
            ("Conversion", Num.pct(d.value(.pageCR))),
            ("Releases", releases.isEmpty ? "None" : releases.suffix(2).joined(separator: " · ")),
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
