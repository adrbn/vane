#if os(macOS)
import AlmanacCore
import Charts
import SwiftUI

/// Insights: the lead insight as hero, then cards grouped by recency. "Nothing to flag" when all is quiet.
struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var category: InsightCategory?
    @State private var showDismissed = false
    @State private var fixing: Insight?
    @State private var asked: String?

    var body: some View {
        let app = model.appId ?? ""
        let active = model.store.insights(app)
        let all = showDismissed ? model.store.insights(app, includeDismissed: true) : active
        let shown = all.filter { category == nil || $0.category == category }
        Screen(title: "Insights", subtitle: subtitle, inspector: true) {
            GlassGroup { categoryMenu(all) }
        } content: {
            if active.isEmpty && !showDismissed {
                NothingToFlag()
            } else if shown.isEmpty {
                Text("No \(category?.title.lowercased() ?? "") insights right now.").font(t.font(13)).foregroundStyle(t.label2)
            } else {
                list(shown)
            }
        }
        .blur(radius: fixing == nil ? 0 : 16)
        .overlay {
            if let f = fixing {
                CenteredSheet(onDismiss: { fixing = nil }) { KeywordFixSheet(insight: f, close: { fixing = nil }) }
            }
        }
        .onAppear { model.chatContext = LegacyInsightsView.context(shown, app: model.app?.name ?? "") }
        .onChange(of: category) { model.chatContext = LegacyInsightsView.context(shown, app: model.app?.name ?? "") }
    }

    private var subtitle: String {
        let name = model.app?.name ?? ""
        guard let d = model.lastSync else { return name }
        return "\(name) · Updated \(d.formatted(.relative(presentation: .named)))"
    }

    private func categoryMenu(_ all: [Insight]) -> some View {
        let counts = Dictionary(grouping: all, by: \.category).mapValues(\.count)
        return Menu {
            Button("All categories") { category = nil }
            Divider()
            ForEach(InsightCategory.allCases.filter { counts[$0] != nil }) { c in
                Button("\(c.title) (\(counts[c] ?? 0))") { category = c }
            }
            Divider()
            Toggle("Show dismissed", isOn: $showDismissed)
        } label: {
            HStack(spacing: 6) {
                Text(category?.title ?? "All categories")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label2)
            }
            .font(t.font(13, .semibold)).padding(.horizontal, 10).frame(height: 28).contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Groups

    private func list(_ shown: [Insight]) -> some View {
        let today = Day.today()
        let new = shown.filter { $0.day >= Day.add(-1, to: today) }
        let week = shown.filter { $0.day < Day.add(-1, to: today) && $0.day >= Day.add(-7, to: today) }
        let older = shown.filter { $0.day < Day.add(-7, to: today) }
        let lead = new.first { $0.needsAttention && !$0.dismissed } ?? new.first
        // A handful of cards reads better as one row than as three half-empty groups; each card carries its date.
        let few = shown.count <= 3 && new.isEmpty
        return VStack(alignment: .leading, spacing: 16) {
            if few {
                group("Recent", "\(shown.count) insight\(shown.count == 1 ? "" : "s") in the last \(Day.between(shown.map(\.day).min() ?? today, today) + 1) days")
                grid(shown)
                // A quiet feed still shows what is being watched, as when there is nothing to flag.
                group("Watching", "Last 28 days against each metric's usual range").padding(.top, 8)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(NothingToFlag.watched, id: \.self) { WatchCard(metric: $0, app: model.appId ?? "") }
                }
            } else {
                if !new.isEmpty {
                    group("New", "\(new.count) since yesterday")
                    if let lead { InsightCardView(insight: lead, lead: true, asked: $asked, fixing: $fixing) }
                    grid(new.filter { $0.id != lead?.id })
                }
                if !week.isEmpty { group("Earlier this week", nil).padding(.top, new.isEmpty ? 0 : 8); grid(week) }
                if !older.isEmpty { group("Earlier", nil).padding(.top, 8); grid(older) }
            }
        }
    }

    private func group(_ title: String, _ sub: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(t.font(15, .bold))
            if let sub { Text(sub).font(t.font(13)).foregroundStyle(t.label2) }
        }
    }

    private func grid(_ items: [Insight]) -> some View {
        // Few cards stretch across the row instead of leaving an empty column.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: items.count == 1 ? 2 : max(1, min(items.count, 3))), spacing: 16) {
            ForEach(items) { InsightCardView(insight: $0, lead: false, asked: $asked, fixing: $fixing) }
        }
    }
}

// MARK: - Card

struct InsightCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.openWindow) private var openWindow
    var insight: Insight
    var lead: Bool
    @Binding var asked: String?
    @Binding var fixing: Insight?
    @State private var wide = true

    var body: some View {
        let highlighted = model.chatOpen && asked == insight.id
        Group {
            if lead, let chart = insight.chart, !chart.isBigNumber {
                // Two columns, stacked under ~600 pt (e.g. with the inspector open).
                let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 32)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                layout {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                    LeadEvidence(insight: insight, chart: chart).frame(maxWidth: .infinity)
                }
                .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { wide = $0 }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    meta
                    Text(insight.title).font(t.font(15, .bold)).fixedSize(horizontal: false, vertical: true)
                    Text(insight.body).font(t.font(13)).foregroundStyle(t.label2).lineLimit(4)
                        .frame(minHeight: 34, alignment: .top).fixedSize(horizontal: false, vertical: true)
                    evidence.frame(minHeight: 56, alignment: .top)
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .themedCard(padding: lead ? 24 : 20, highlighted: highlighted || (lead && insight.needsAttention))
        .opacity(insight.dismissed ? 0.55 : 1)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 10) {
            meta
            Text(insight.title).font(t.font(22, .bold)).tracking(-0.2).fixedSize(horizontal: false, vertical: true)
            Text(insight.body).font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions
        }
    }

    private var meta: some View {
        HStack(spacing: 8) {
            IconSquare(symbol: insight.category.symbol, style: t.square(insight.category.section), size: 20)
            Text(insight.category.title).font(t.font(12, .semibold)).foregroundStyle(t.label2)
            Spacer(minLength: 4)
            Text(Self.when(insight.day)).font(t.font(12)).foregroundStyle(t.label2)
            if !insight.dismissed {
                Button { withAnimation(.snappy) { model.dismiss(insight) } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label3)
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Dismiss")
            }
        }
    }

    static func when(_ day: String) -> String {
        let today = Day.today()
        if day == today { return "Today" }
        if day == Day.add(-1, to: today) { return "Yesterday" }
        return Day.date(day).formatted(.dateTime.month(.abbreviated).day())
    }

    @ViewBuilder private var evidence: some View {
        if case .fixKeywords(let locale, _)? = insight.action {
            KeywordEvidence(appId: insight.appId, locale: locale)
        } else if let chart = insight.chart {
            if chart.isBigNumber {
                Text(chart.headline).font(t.font(40, .bold)).monospacedDigit().foregroundStyle(t.accentText)
            } else {
                MiniInsightChart(chart: chart, color: chartColor)
                    .frame(height: 64)
            }
        }
    }

    /// The metric's own color when the insight is about one metric.
    private var chartColor: Color {
        if case .openMetric(let m)? = insight.action, let metric = Metric(rawValue: m) { return t.color(metric) }
        return t.accent
    }

    private var actions: some View {
        HStack(spacing: 8) {
            SmallButton(label: "Ask", symbol: "sparkles") {
                asked = insight.id
                model.ask("Explain this insight and what I should do about it: \(insight.title). \(insight.body)")
            }
            switch insight.action {
            case .fixKeywords: SmallButton(label: "Fix…", prominent: true) { fixing = insight }
            case .openReport(let p, let s):
                SmallButton(label: "Read Report") {
                    openWindow(id: "report", value: ReportRef(appId: insight.appId, period: ReportPeriod(rawValue: p) ?? .week, start: s))
                }
            case .openMetric(let m): SmallButton(label: "Open") { open(m) }
            case nil: EmptyView()
            }
        }
    }

    private func open(_ m: String) {
        switch m {
        case "listing": model.section = .listing
        case "reviews": model.section = .reviews
        case "territories": model.section = .territories
        case "sales": model.section = .sales
        default: if let metric = Metric(rawValue: m) { model.section = .metric(metric) }
        }
    }
}

extension InsightCategory {
    var section: AlmanacTheme.Section {
        switch self {
        case .discovery: .listing
        case .conversion, .ratings: .reviews
        case .revenue: .sales
        case .markets: .territories
        case .retention: .usage
        case .milestones: .insights
        case .reports: .appstore
        }
    }
}

/// Lead card right column: value, change against the baseline, chart with releases.
private struct LeadEvidence: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var insight: Insight
    var chart: InsightChart

    var body: some View {
        let versions = model.store.versions(insight.appId).filter { v in
            guard let a = chart.points.first?.day, let b = chart.points.last?.day else { return false }
            return v.day >= a && v.day <= b
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(chart.headline).font(t.font(40, .bold)).tracking(-0.8).monospacedDigit()
            if let l = chart.baselineLabel { Text(l).font(t.font(13)).foregroundStyle(t.label2).monospacedDigit() }
            MiniInsightChart(chart: chart, color: insight.needsAttention ? t.neg : t.accent, versions: versions, baselineLabel: false)
                .frame(height: 96).padding(.top, 12)
            HStack {
                if let a = chart.points.first { Text(InsightCardView.when(a.day)) }
                Spacer()
                if let b = chart.points.last { Text(InsightCardView.when(b.day)) }
            }
            .font(t.font(10)).foregroundStyle(t.label2)
        }
    }
}

/// Small chart with a dashed baseline, optional release rules, and a dot on the last point.
struct MiniInsightChart: View {
    @Environment(\.theme) private var t
    var chart: InsightChart
    var color: Color
    var versions: [VersionMark] = []
    var baselineLabel = true

    var body: some View {
        Chart {
            ForEach(chart.points) { p in
                AreaMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.25), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .foregroundStyle(color).lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let b = chart.baseline {
                RuleMark(y: .value("Baseline", b)).foregroundStyle(t.label3).lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        if baselineLabel, let l = chart.baselineLabel { Text(l).font(t.font(10)).foregroundStyle(t.label2) }
                    }
            }
            ForEach(versions) { v in
                RuleMark(x: .value("Release", Day.date(v.day))).foregroundStyle(t.label2.opacity(0.5)).lineStyle(.init(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("\(Day.date(v.day).formatted(.dateTime.month(.abbreviated).day())) · \(v.version)").font(t.font(10, .semibold)).foregroundStyle(t.label2)
                    }
            }
            if let p = chart.points.last {
                PointMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .symbol { Circle().fill(color).frame(width: 8, height: 8).overlay(Circle().strokeBorder(t.card, lineWidth: 1.5)) }
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
    }
}

/// The keyword field with words already in the name or subtitle struck through.
private struct KeywordEvidence: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var appId: String
    var locale: String

    var body: some View {
        if let l = model.store.listing(appId).first(where: { $0.locale == locale }) {
            let taken = Set((l.name + " " + l.subtitle).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let terms = l.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            terms.enumerated().reduce(Text("")) { acc, e in
                let repeated = e.element.lowercased().split { !$0.isLetter && !$0.isNumber }.contains { taken.contains(String($0)) }
                let word = repeated ? Text(e.element).strikethrough(color: t.warn).foregroundStyle(t.warn).fontWeight(.semibold) : Text(e.element)
                return acc + word + Text(e.offset < terms.count - 1 ? ", " : "")
            }
            .font(t.font(12)).foregroundStyle(t.label2).lineLimit(4)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(t.fill, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
        }
    }
}

// MARK: - Nothing to flag

private struct NothingToFlag: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    static let watched: [Metric] = [.firstDownloads, .ttr, .pageCR, .redownloads, .impressions, .pageViews]

    /// Analytics metrics have nothing until Apple's first report; never present them as "normal".
    static func hasData(_ store: Store, _ app: String, _ m: Metric) -> Bool {
        switch m {
        case .impressions, .pageViews, .ttr, .pageCR: store.lastDay(app, .impressions) != nil
        default: store.lastDay(app, m) != nil
        }
    }

    var body: some View {
        let app = model.appId ?? ""
        let resolved = model.store.insights(app, includeDismissed: true).filter(\.dismissed).prefix(5)
        let live = Self.watched.filter { Self.hasData(model.store, app, $0) }.count
        VStack(alignment: .leading, spacing: 24) {
            status(live)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Watching").font(t.font(15, .bold))
                    Text("Last 28 days against each metric's usual range").font(t.font(13)).foregroundStyle(t.label2).lineLimit(1)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(Self.watched, id: \.self) { WatchCard(metric: $0, app: app) }
                }
            }
            if !resolved.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recently resolved").font(t.font(15, .bold))
                    VStack(spacing: 0) {
                        ForEach(Array(resolved.enumerated()), id: \.element.id) { i, r in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(t.pos)
                                Text(r.title).font(t.font(13)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("Dismissed · flagged \(InsightCardView.when(r.day))").font(t.font(12)).foregroundStyle(t.label2)
                            }
                            .padding(.horizontal, 20).frame(height: 44)
                            .overlay(alignment: .top) { if i > 0 { t.sep.frame(height: 1) } }
                        }
                    }
                    .themedCard(padding: 0)
                }
            }
        }
    }

    private func status(_ live: Int) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundStyle(t.accentText)
                .frame(width: 52, height: 52).background(t.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing to flag").font(t.font(26, .bold)).tracking(-0.26)
                Text(live == Self.watched.count
                     ? "Almanac compared \(live) metrics with their usual range. Everything is normal, so there is nothing to act on today. New insights appear here when a metric leaves its range or a review needs you."
                     : "Almanac watches \(live) of \(Self.watched.count) metrics so far and none needs you. The others start once Apple's first analytics report arrives, usually 24–48 hours after you connect.")
                    .font(t.font(14)).foregroundStyle(t.label2).frame(maxWidth: 560, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                if let d = model.lastSync {
                    Text("Checked \(d.formatted(.relative(presentation: .named))) · Checks again after every refresh")
                        .font(t.font(12)).foregroundStyle(t.label2).padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
            SmallButton(label: model.syncing ? "Checking…" : "Check Now") { Task { await model.refresh() } }.disabled(model.syncing)
        }
        .themedCard(padding: 28)
    }
}

/// Daily average over 28 days, the usual range (10th–90th percentile of the 63 days before), a sparkline over the band.
private struct WatchCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var metric: Metric
    var app: String

    var body: some View {
        let to = model.store.lastDay(app, metric) ?? Day.today()
        let from = Day.add(-27, to: to)
        let recent = model.store.series(app, metric, from: from, to: to).map(\.value)
        let before = model.store.series(app, metric, from: Day.add(-63, to: Day.add(-1, to: from)), to: Day.add(-1, to: from)).map(\.value).sorted()
        let avg = metric.isRate ? model.store.total(app, metric, from: from, to: to) : recent.reduce(0, +) / Double(max(recent.count, 1))
        let band: (Double, Double)? = before.count >= 28 ? (before[before.count / 10], before[before.count * 9 / 10]) : nil
        let has = NothingToFlag.hasData(model.store, app, metric)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    IconSquare(symbol: MetricCard.symbol(metric), style: t.square(metric), size: 20)
                    Text(MetricCard.label(metric)).font(t.font(13, .semibold)).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(has ? (metric.isRate ? Num.pct(avg) : Num.k(avg)) : "—").font(t.font(24, .bold)).monospacedDigit()
                        .foregroundStyle(has ? t.label : t.label3)
                    if has && !metric.isRate { Text("a day").font(t.font(12)).foregroundStyle(t.label2) }
                }
                Text(!has ? "Waiting for Apple's first report" : band.map { "Usual \(fmt($0.0))–\(fmt($0.1))" } ?? "Usual range after 13 weeks of data")
                    .font(t.font(11)).foregroundStyle(t.label2).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 0)
            BandSpark(values: has ? recent : [], band: band, color: t.color(metric))
                .frame(width: 96, height: 48)
        }
        .themedCard(padding: 16)
    }

    private func fmt(_ v: Double) -> String { metric.isRate ? Num.pct(v) : Num.k(v) }
}

private struct BandSpark: View {
    @Environment(\.theme) private var t
    var values: [Double]
    var band: (Double, Double)?
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let lo = min(values.min()!, band?.0 ?? .infinity), hi = max(values.max()!, band?.1 ?? -.infinity)
            let span = max(hi - lo, 1e-9) * 1.2, base = lo - (hi - lo) * 0.1
            let y: (Double) -> CGFloat = { size.height * (1 - CGFloat(($0 - base) / span)) }
            if let band {
                ctx.fill(Path(CGRect(x: 0, y: y(band.1), width: size.width, height: y(band.0) - y(band.1))), with: .color(t.fill))
            }
            var p = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1), y: y(v))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
#endif
