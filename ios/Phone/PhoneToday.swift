import AlmanacCore
import SwiftUI

/// Screens pushed from any tab.
enum PhoneRoute: Hashable {
    case metric(Metric, days: Int)
    case territories(days: Int)
    case report
    case settings
    case about
}

extension View {
    func phoneDestinations() -> some View {
        navigationDestination(for: PhoneRoute.self) { r in
            switch r {
            case .metric(let m, let days): PhoneMetric(metric: m, days: days)
            case .territories(let days): PhoneTerritories(days: days)
            case .report: PhoneReport()
            case .settings: PhoneSettings()
            case .about: PushedScreen(title: String(localized: "About"), subtitle: "") { AboutView() }
            }
        }
    }
}

/// Today: yesterday's downloads, the weekly report, then the insights.
struct TodayScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Binding var tab: PhoneTab

    var body: some View {
        let _ = model.revision
        let app = model.appId ?? ""
        let insights = model.insights()
        PhoneScreen(title: String(localized: "Today"), subtitle: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.current))) {
            NavigationLink(value: PhoneRoute.settings) { PhoneIconLabel(symbol: "gearshape") }.buttonStyle(.plain)
        } content: {
            if model.isDemo { PhoneDemoNote() }
            yesterday(app)
            NavigationLink(value: PhoneRoute.report) {
                HStack(spacing: 12) {
                    IconSquare(symbol: "doc.text", style: t.square(.insights), size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Weekly report").font(t.font(15, .semibold))
                        Text("Last full week, written from your numbers").font(t.font(12)).foregroundStyle(t.label2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.label3)
                }
                .phoneCard(padding: 14)
            }
            .buttonStyle(.plain)
            PhoneSectionTitle(title: String(localized: "Insights"), detail: insights.isEmpty ? "" : "\(insights.count)")
            if insights.isEmpty {
                Text("Nothing new. Vane writes one when a number moves outside its usual range.")
                    .font(t.font(13)).foregroundStyle(t.label2).phoneCard()
            }
            ForEach(insights) { PhoneInsightCard(insight: $0, tab: $tab) }
            Text("Insights come from fixed rules run on your numbers. No AI writes them. Turn categories off in Settings.")
                .font(t.font(12)).foregroundStyle(t.label3).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
        .phoneDestinations()
    }

    @ViewBuilder private func yesterday(_ app: String) -> some View {
        let s = model.store.series(app, .firstDownloads)
        if let last = s.last {
            let prior = s.dropLast()
            let weekAgo = s.last { $0.day == Day.add(-7, to: last.day) }
            let best = prior.allSatisfy { $0.value < last.value } && prior.count > 6
            let c = weekAgo.map { Change(.firstDownloads, value: last.value, previous: $0.value, arrows: true) }
            NavigationLink(value: PhoneRoute.metric(.firstDownloads, days: 28)) {
                PhoneHero(label: String(localized: "First-time downloads · \(InsightCardView.when(last.day))"),
                          value: Num.int(last.value),
                          caption: best ? Text("Best day ever").fontWeight(.bold)
                              : c.map { Text($0.text).fontWeight(.bold) + Text(" on the same day last week") } ?? Text(AppStoreData.md(last.day)),
                          spark: s.suffix(28).map(\.value))
            }
            .buttonStyle(.plain)
        } else {
            Text("No downloads yet. Sales reports arrive a day after the first sale.")
                .font(t.font(13)).foregroundStyle(t.label2).phoneCard()
        }
    }
}

/// Glyph in a 38 pt glass circle, for NavigationLinks in the nav row.
struct PhoneIconLabel: View {
    @Environment(\.theme) private var t
    var symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.label)
            .frame(width: 38, height: 38)
            .background(t.glass, in: Circle())
            .overlay(Circle().strokeBorder(t.glassBorder, lineWidth: 1))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
}

struct PhoneDemoNote: View {
    @Environment(\.theme) private var t
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(t.accentText)
            Text("Demo data · three made-up apps").font(t.font(12)).foregroundStyle(t.label2)
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(t.accentSoft, in: Capsule())
    }
}

/// One insight: category, title, body, small chart, and where to go next.
struct PhoneInsightCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var insight: Insight
    @Binding var tab: PhoneTab

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconSquare(symbol: insight.category.symbol, style: t.square(insight.category.section), size: 22)
                Text(insight.category.title).font(t.font(12, .semibold)).foregroundStyle(t.label2)
                Spacer()
                Text(InsightCardView.when(insight.day)).font(t.font(12)).foregroundStyle(t.label2)
                Button { withAnimation(.snappy) { model.dismiss(insight) } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(t.label3)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
                .padding(.vertical, -8).padding(.trailing, -8)
            }
            Text(insight.title).font(t.font(17, .bold)).fixedSize(horizontal: false, vertical: true)
            Text(insight.body).font(t.font(14)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
            if let chart = insight.chart {
                if chart.isBigNumber {
                    Text(chart.headline).font(t.font(36, .bold)).monospacedDigit().foregroundStyle(t.accentText)
                } else {
                    MiniInsightChart(chart: chart, color: color).frame(height: 64)
                }
            }
            action
        }
        .phoneCard()
    }

    private var color: Color {
        if case .openMetric(let m)? = insight.action, let metric = Metric(rawValue: m) { return t.color(metric) }
        return t.accent
    }

    @ViewBuilder private var action: some View {
        switch insight.action {
        case .fixKeywords: SmallButton(label: String(localized: "Fix in Listing"), prominent: true) { tab = .listing }
        case .openReport: NavigationLink(value: PhoneRoute.report) { linkLabel(String(localized: "Read Report")) }.buttonStyle(.plain)
        case .openMetric(let m):
            switch m {
            case "listing": SmallButton(label: String(localized: "Open Listing")) { tab = .listing }
            case "reviews": SmallButton(label: String(localized: "Open Reviews")) { tab = .reviews }
            case "territories": NavigationLink(value: PhoneRoute.territories(days: 28)) { linkLabel(String(localized: "Open")) }.buttonStyle(.plain)
            case "sales": SmallButton(label: String(localized: "Open Sales")) { tab = .appStore }
            default:
                if let metric = Metric(rawValue: m) {
                    NavigationLink(value: PhoneRoute.metric(metric, days: 28)) { linkLabel(String(localized: "Open")) }.buttonStyle(.plain)
                }
            }
        case nil: EmptyView()
        }
    }

    private func linkLabel(_ s: String) -> some View {
        Text(s).font(t.font(13, .semibold)).foregroundStyle(t.label)
            .padding(.horizontal, 12).frame(height: 28)
            .background(t.fill, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
    }
}

/// Weekly / Monthly / Yearly report for the last complete period.
struct PhoneReport: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var period: ReportPeriod = .week

    var body: some View {
        let app = model.appId ?? ""
        let r = report(app)
        PushedScreen(title: period.reportTitle, subtitle: r.map { "\($0.appName) · \($0.periodLabel)" } ?? "") {
            PhoneSegments(options: ReportPeriod.allCases.map { ($0, $0.title) }, selection: $period)
            if let r {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(r.headline.prefix(4)) { k in
                        PhoneTile(metric: k.metric, label: k.metric.title, value: Num.value(k.metric, k.value),
                                  change: k.previous > 0 ? Change(k.metric, value: k.value, previous: k.previous) : nil,
                                  note: k.previous > 0 ? nil : String(localized: "No earlier data"))
                    }
                }
                block(String(localized: "Summary"), [r.summary])
                if let first = r.headline.first, first.spark.contains(where: { $0.value > 0 }) {
                    PhoneBars(points: first.spark, color: t.color(first.metric)).frame(height: 120).phoneCard()
                }
                ForEach(Array(r.sections.enumerated()), id: \.offset) { _, s in block(s.heading, s.paragraphs) }
            } else {
                (period == .week ? Text("Not enough data for a full week yet.") : period == .month ? Text("Not enough data for a full month yet.") : Text("Not enough data for a full year yet.")).font(t.font(13)).foregroundStyle(t.label2).phoneCard()
            }
        }
    }

    private func block(_ title: String, _ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(t.font(17, .bold))
            ForEach(paragraphs, id: \.self) { Text($0).font(t.font(15)).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.top, 8)
    }

    /// Steps back from the latest day until the whole period has data, so a report never compares half a week.
    private func report(_ app: String) -> Report? {
        guard let last = model.store.lastDay(app) else { return nil }
        let builder = ReportBuilder(store: model.store, app: app)
        let c: Calendar.Component = period == .week ? .weekOfYear : period == .month ? .month : .year
        var start = Self.start(period, last)
        for _ in 0..<3 {
            let r = builder.build(period, start: start)
            if r.end <= last { return r }
            start = Day.string(Day.calendar.date(byAdding: c, value: -1, to: Day.date(start))!)
        }
        return nil
    }

    static func start(_ p: ReportPeriod, _ day: String) -> String {
        switch p {
        case .week: Day.weekStart(day)
        case .month: Day.monthStart(day)
        case .year: Day.yearStart(day)
        }
    }
}

/// Daily bars, flat-topped, no axes.
struct PhoneBars: View {
    var points: [Point]
    var color: Color
    var body: some View {
        let hi = max(points.map(\.value).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: points.count > 40 ? 1 : 3) {
            ForEach(points, id: \.day) { p in
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color)
                    .frame(maxWidth: .infinity).frame(height: max(2, CGFloat(p.value / hi) * 100))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
