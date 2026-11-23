import AlmanacCore
import Charts
import SwiftUI

enum StoreSegment: Hashable { case appStore, sales, usage }

/// App Store tab: App Store / Sales / Usage, with the period in a menu.
struct AppStoreTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var segment: StoreSegment = .appStore
    @AppStorage("phone.days") private var days = 28

    var body: some View {
        let _ = model.revision
        let d = AppStoreData(store: model.store, app: model.appId ?? "", days: days)
        PhoneScreen(title: title, subtitle: d.range) {
            PeriodMenu(days: $days)
        } content: {
            PhoneSegments(options: [(.appStore, String(localized: "App Store")), (.sales, String(localized: "Sales")), (.usage, String(localized: "Usage"))], selection: $segment)
                .padding(.bottom, 4)
            switch segment {
            case .appStore: appStore(d)
            case .sales: sales(d)
            case .usage: usage(d)
            }
        }
        .phoneDestinations()
    }

    private var title: String { segment == .appStore ? String(localized: "App Store") : segment == .sales ? String(localized: "Sales") : String(localized: "Usage") }

    @ViewBuilder private func appStore(_ d: AppStoreData) -> some View {
        let c = d.change(.firstDownloads)
        link(.firstDownloads) {
            PhoneHero(label: String(localized: "First-time downloads, last \(d.per)"), value: d.shown(.firstDownloads),
                      caption: Text(c.text).fontWeight(.bold) + Text(c.text == Change.noHistory.text ? "" : String(localized: " on the previous \(d.per)")),
                      spark: d.spark(.firstDownloads))
        }
        if !d.pending { PhoneFunnel(d: d) }
        grid {
            ForEach([Metric.impressions, .pageViews, .ttr, .pageCR, .redownloads], id: \.self) { m in
                link(m) { tile(d, m) }
            }
            NavigationLink(value: PhoneRoute.territories(days: days)) { territoryTile(d) }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private func sales(_ d: AppStoreData) -> some View {
        let c = d.change(.proceeds)
        link(.proceeds) {
            PhoneHero(label: String(localized: "Proceeds, last \(d.per)"), value: d.shown(.proceeds),
                      caption: Text(c.text).fontWeight(.bold) + Text(c.text == Change.noHistory.text ? "" : String(localized: " on the previous \(d.per)")),
                      spark: d.spark(.proceeds))
        }
        grid {
            link(.sales) { tile(d, .sales) }
            link(.downloads) { tile(d, .downloads) }
            link(.activeSubs) {
                let last = model.store.series(model.appId ?? "", .activeSubs).last?.value
                PhoneTile(metric: nil, label: String(localized: "Active subscriptions"), value: last.map(Num.int) ?? "—", change: nil, note: String(localized: "Latest count"))
            }
            link(.firstDownloads) { tile(d, .firstDownloads) }
        }
    }

    @ViewBuilder private func usage(_ d: AppStoreData) -> some View {
        let app = model.appId ?? ""
        let to = model.store.lastDay(app, .sessions)
        let from = to.map { Day.add(-(days - 1), to: $0) }
        let sessions = from.map { model.store.total(app, .sessions, from: $0, to: to!) } ?? 0
        let crashes = from.map { model.store.total(app, .crashes, from: $0, to: to!) } ?? 0
        if to == nil {
            Text("Usage comes from Apple's analytics report, one or two days after the first install.")
                .font(t.font(13)).foregroundStyle(t.label2).phoneCard()
        } else {
            link(.sessions) {
                PhoneHero(label: String(localized: "Sessions, last \(d.per)"), value: Num.k(sessions),
                          caption: Text("Crash rate ") + Text(sessions > 0 ? String(format: "%.2f%%", crashes / sessions * 100) : "—").fontWeight(.bold),
                          spark: model.store.series(app, .sessions, from: from!, to: to!).map(\.value))
            }
            grid {
                link(.crashes) { PhoneTile(metric: nil, label: String(localized: "Crashes"), value: Num.int(crashes), change: nil, note: String(localized: "Last \(d.per)")) }
                link(.ratingsTotal) {
                    PhoneTile(metric: nil, label: String(localized: "Ratings"), value: model.store.series(app, .ratingsTotal).last.map { Num.int($0.value) } ?? "—", change: nil, note: String(localized: "All time"))
                }
                link(.newRatings) { tile(d, .newRatings) }
                link(.updates) {
                    PhoneTile(metric: nil, label: String(localized: "Updates"), value: Num.int(model.store.total(app, .updates, from: from!, to: to!)), change: nil, note: String(localized: "Last \(d.per)"))
                }
                let r = model.store.retention(app, from: from!, to: to!)
                PhoneTile(metric: nil, label: String(localized: "Retention"), value: r.first?.rate.map(Num.pct) ?? "—", change: nil,
                          note: r.dropFirst().map { "D\($0.day) \($0.rate.map(Num.pct) ?? "—")" }.joined(separator: " · "))
            }
        }
    }

    private func tile(_ d: AppStoreData, _ m: Metric) -> some View {
        PhoneTile(metric: m, label: m == .pageCR ? String(localized: "Conversion") : m == .pageViews ? String(localized: "Page views") : m.title,
                  value: d.shown(m), change: d.has(m) && d.hasPrevious(m) ? d.change(m) : nil,
                  note: d.has(m) ? String(localized: "No earlier data") : AnalyticsPending.expected, spark: d.has(m) ? d.spark(m) : [])
    }

    private func territoryTile(_ d: AppStoreData) -> some View {
        let td = TerritoryData(store: model.store, app: model.appId ?? "", days: days)
        return PhoneTile(metric: nil, label: String(localized: "Territories"), value: td.largest.map { Territories.flag($0.code) + " " + $0.code } ?? "—",
                         change: nil, note: td.largest.map { String(localized: "\(Num.pct($0.share)) of downloads") } ?? String(localized: "No downloads yet"))
    }

    private func link<C: View>(_ m: Metric, @ViewBuilder _ c: () -> C) -> some View {
        NavigationLink(value: PhoneRoute.metric(m, days: days)) { c() }.buttonStyle(.plain)
    }

    private func grid<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) { c() }
    }
}

/// "28 days ⌄" glass pill.
struct PeriodMenu: View {
    @Environment(\.theme) private var t
    @Binding var days: Int
    static let options = [(7, String(localized: "7 days")), (28, String(localized: "28 days")), (90, String(localized: "90 days")), (365, String(localized: "1 year"))]
    var body: some View {
        Menu {
            Picker("Period", selection: $days) { ForEach(Self.options, id: \.0) { Text($0.1).tag($0.0) } }
        } label: {
            HStack(spacing: 6) {
                Text(Self.options.first { $0.0 == days }?.1 ?? String(localized: "\(days) days")).font(t.font(14, .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label2)
            }
            .foregroundStyle(t.label)
            .padding(.horizontal, 14).frame(height: 38)
            .background(t.glass, in: Capsule())
            .overlay(Capsule().strokeBorder(t.glassBorder, lineWidth: 1))
        }
    }
}

// MARK: - Metric detail

struct PhoneMetric: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let metric: Metric
    @State var days: Int
    @State private var compare = false
    @State private var selected: Date?

    var body: some View {
        let d = MetricData(store: model.store, app: model.appId ?? "", metric: metric, days: days, territory: "")
        let color = t.color(metric, up: d.value >= d.previous)
        PushedScreen(title: metric.title, subtitle: d.rangeLabel) {
            PhoneSegments(options: PeriodMenu.options.map { ($0.0, $0.0 == 365 ? String(localized: "1Y") : String(localized: "\($0.0)D")) }, selection: $days)
            VStack(alignment: .leading, spacing: 4) {
                Text(MetricData.full(metric, d.value)).font(t.font(44, .heavy)).tracking(-1.2).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                if d.hasPrevious {
                    let c = Change(metric, value: d.value, previous: d.previous)
                    (Text(c.text).foregroundStyle(c.color(t, invert: metric == .crashes)).fontWeight(.bold)
                        + Text(" vs \(MetricData.full(metric, d.previous)) the period before").foregroundStyle(t.label2))
                        .font(t.font(14))
                }
            }
            chart(d, color).frame(height: 220).phoneCard(padding: 14)
            if d.hasLastYear {
                Toggle(isOn: $compare) { Text("Compare with last year").font(t.font(15, .semibold)) }
                    .tint(t.accent).phoneCard(padding: 14)
            }
            PhoneSectionTitle(title: d.g == .week ? String(localized: "Recent weeks") : String(localized: "Recent days"))
            VStack(spacing: 0) {
                ForEach(Array(d.rows.reversed().prefix(10).enumerated()), id: \.element.id) { i, r in
                    HStack {
                        Text(d.label(r.day)).font(t.font(14)).foregroundStyle(t.label2)
                        Spacer()
                        if compare, let ly = r.lastYear { Text(MetricData.full(metric, ly)).font(t.font(13)).foregroundStyle(t.label3).monospacedDigit() }
                        Text(MetricData.full(metric, r.value)).font(t.font(15, .semibold)).monospacedDigit()
                    }
                    .padding(.horizontal, 16).frame(height: 44)
                    if i < 9 { Divider().overlay(t.sep).padding(.leading, 16) }
                }
            }
            .phoneCard(padding: 0)
        }
    }

    private func chart(_ d: MetricData, _ color: Color) -> some View {
        let pick = selected.flatMap { s in d.rows.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
        return Chart {
            ForEach(d.rows) { r in
                AreaMark(x: .value("Day", r.date), y: .value("Value", r.value))
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.25), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", r.date), y: .value("Value", r.value), series: .value("S", "now"))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if compare, let ly = r.lastYear {
                    LineMark(x: .value("Day", r.date), y: .value("Value", ly), series: .value("S", "ly"))
                        .foregroundStyle(t.label3).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            ForEach(d.versions) { v in
                RuleMark(x: .value("Release", Day.date(v.day)))
                    .foregroundStyle(t.label3).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) { Text(v.version).font(t.font(10, .semibold)).foregroundStyle(t.label2) }
            }
            if let pick {
                RuleMark(x: .value("Selected", pick.date)).foregroundStyle(t.label2)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(MetricData.full(metric, pick.value)).font(t.font(13, .bold)).monospacedDigit()
                            Text(d.label(pick.day)).font(t.font(11)).foregroundStyle(t.label2)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(t.popover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(t.sep); AxisValueLabel().foregroundStyle(t.label2) } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(t.label2) } }
    }
}

// MARK: - Territories

struct PhoneTerritories: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let days: Int

    var body: some View {
        let d = TerritoryData(store: model.store, app: model.appId ?? "", days: days)
        let top = d.rows.filter { $0.downloads > 0 }.sorted { $0.downloads > $1.downloads }
        PushedScreen(title: String(localized: "Territories"), subtitle: String(localized: "First-time downloads, last \(days) days")) {
            ThemedWorldMap(values: Dictionary(uniqueKeysWithValues: d.rows.map { ($0.code, $0.downloads) }),
                           bins: ThemedWorldMap.bins(top.first?.downloads ?? 0))
                .frame(height: 190).phoneCard(padding: 12)
            VStack(spacing: 0) {
                fact(String(localized: "Largest"), d.largest.map { "\(Territories.flag($0.code)) \($0.name)" }, d.largest.map { "\(Num.int($0.downloads)) · \(Num.pct($0.share))" })
                Divider().overlay(t.sep).padding(.leading, 16)
                fact(String(localized: "Fastest growing"), d.fastest.map { "\(Territories.flag($0.row.code)) \($0.row.name)" }, d.fastest?.change.text)
                Divider().overlay(t.sep).padding(.leading, 16)
                fact(String(localized: "Best conversion"), d.bestConversion.map { "\(Territories.flag($0.code)) \($0.name)" }, d.bestConversion?.conversion.map(Num.pct))
            }
            .phoneCard(padding: 0)
            PhoneSectionTitle(title: String(localized: "Top 5"))
            VStack(spacing: 0) {
                ForEach(Array(top.prefix(5).enumerated()), id: \.element.id) { i, r in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(t.font(13, .semibold)).foregroundStyle(t.label3).frame(width: 16)
                        Text("\(Territories.flag(r.code)) \(r.name)").font(t.font(15)).lineLimit(1)
                        Spacer()
                        if let c = r.change { Text(c.text).font(t.font(12, .semibold)).foregroundStyle(c.color(t)) }
                        Text(Num.int(r.downloads)).font(t.font(15, .semibold)).monospacedDigit()
                    }
                    .padding(.horizontal, 16).frame(height: 48)
                    if i < min(top.count, 5) - 1 { Divider().overlay(t.sep).padding(.leading, 16) }
                }
            }
            .phoneCard(padding: 0)
        }
    }

    private func fact(_ label: String, _ value: String?, _ detail: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(t.font(12)).foregroundStyle(t.label2)
                Text(value ?? "—").font(t.font(15, .semibold)).lineLimit(1)
            }
            Spacer()
            Text(detail ?? "").font(t.font(14, .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 16).frame(height: 56)
    }
}

/// Seen, opened, downloaded: the Mac's funnel, stacked for a phone.
struct PhoneFunnel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let d: AppStoreData

    var body: some View {
        // Downloads on the days the impressions cover, so the three numbers describe the same people.
        let imp = d.value(.impressions), pv = d.value(.pageViews), dl = imp * d.value(.pageCR)
        let ttr = d.change(.ttr), conv = d.change(.pageCR)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("From seen to downloaded").font(t.font(17, .bold))
                Text("Of every 1,000 people who saw \(model.app?.name ?? "your app"), \(imp > 0 ? Num.int(pv / imp * 1000) : "0") opened its page and \(Num.int(d.value(.pageCR) * 1000)) downloaded it.")
                    .font(t.font(13)).foregroundStyle(t.label2).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
            stage(Num.k(imp), Text("saw it in the App Store"), share: 1, color: color(.impressions))
            stage(Num.k(pv), Text("opened the page · ") + Text(Num.pct(d.value(.ttr))).foregroundStyle(ttr.color(t)).fontWeight(.bold), share: imp > 0 ? pv / imp : 0, color: color(.pageViews))
            stage(Num.int(dl), Text("downloaded · ") + Text(Num.pct(d.value(.pageCR))).foregroundStyle(conv.color(t)).fontWeight(.bold), share: d.value(.pageCR), color: color(.firstDownloads))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .phoneCard()
    }

    private func color(_ m: Metric) -> Color { t.colorByDirection ? (m == .firstDownloads ? t.pos : t.label) : t.color(m) }

    private func stage(_ value: String, _ caption: Text, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value).font(t.font(26, t.numWeight)).monospacedDigit().lineLimit(1)
                caption.font(t.font(13)).foregroundStyle(t.label2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.fill)
                    Capsule().fill(color).frame(width: max(10, g.size.width * share))
                }
            }
            .frame(height: 10)
        }
    }
}
