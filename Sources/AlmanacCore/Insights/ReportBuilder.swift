import Foundation

public enum ReportPeriod: String, CaseIterable, Identifiable, Sendable, Codable {
    case week, month, year
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized + "ly" }
}

public struct Report: Sendable {
    public struct KPI: Identifiable, Sendable {
        public var metric: Metric
        public var value: Double
        public var previous: Double
        public var spark: [Point]
        public var id: String { metric.rawValue }
        public var change: Double? { previous > 0 ? value / previous - 1 : nil }
    }
    public struct Section: Identifiable, Sendable {
        public var heading: String
        public var paragraphs: [String]
        public var id: String { heading }
    }
    public var appName: String
    public var period: ReportPeriod
    public var start: String
    public var end: String
    public var periodLabel: String
    public var kpis: [KPI]
    /// What the report window leads with: the analytics funnel when Apple's analytics exist, sales figures otherwise.
    public var headline: [KPI]
    public var hasAnalytics: Bool
    public var summary: String
    public var sections: [Section]

    /// Plain-text version: what the AI chat gets as context.
    public var plainText: String {
        var s = "\(period.title) report for \(appName), \(periodLabel)\n"
        for k in kpis { s += "- \(k.metric.title): \(k.metric.format(k.value)) (previous \(k.metric.format(k.previous)))\n" }
        s += "\n" + summary + "\n"
        for sec in sections { s += "\n## \(sec.heading)\n" + sec.paragraphs.joined(separator: "\n") + "\n" }
        return s
    }
}

/// Builds period reports from stored numbers. Prose is templated so it's always
/// right; the chat can then rewrite or explain it.
public struct ReportBuilder {
    let store: Store
    let app: String
    public init(store: Store, app: String) { self.store = store; self.app = app }

    public func build(_ period: ReportPeriod, start: String) -> Report {
        let end: String, prevStart: String
        switch period {
        case .week: end = Day.add(6, to: start); prevStart = Day.add(-7, to: start)
        case .month:
            let next = Day.string(Day.calendar.date(byAdding: .month, value: 1, to: Day.date(start))!)
            end = Day.add(-1, to: next)
            prevStart = Day.string(Day.calendar.date(byAdding: .month, value: -1, to: Day.date(start))!)
        case .year:
            end = Day.add(-1, to: Day.string(Day.calendar.date(byAdding: .year, value: 1, to: Day.date(start))!))
            prevStart = Day.string(Day.calendar.date(byAdding: .year, value: -1, to: Day.date(start))!)
        }
        let prevEnd = Day.add(-1, to: start)
        func kpi(_ m: Metric) -> Report.KPI {
            let g: Granularity = period == .year ? .month : .day
            return .init(metric: m, value: store.total(app, m, from: start, to: end), previous: store.total(app, m, from: prevStart, to: prevEnd),
                         spark: store.series(app, m, from: start, to: end).bucketed(g, average: m.isGauge))
        }
        let k = [kpi(.downloads), kpi(.pageCR), kpi(.newRatings), kpi(.sales), kpi(.activeSubs)]
        let (dl, cr, ratings, sales, subs) = (k[0], k[1], k[2], k[3], k[4])
        let analytics = store.lastDay(app, .impressions) != nil
        let headline = analytics
            ? [kpi(.firstDownloads), kpi(.impressions), kpi(.ttr), cr, kpi(.proceeds)]
            : [dl, kpi(.proceeds), ratings, subs].enumerated().filter { $0.offset == 0 || $0.element.value > 0 || $0.element.previous > 0 }.map(\.element)
        let name = store.apps().first { $0.id == app }?.name ?? "Your app"

        func change(_ x: Report.KPI) -> String {
            guard let c = x.change else { return "with no earlier figure to compare" }
            if abs(c) < 0.005 { return "flat on the period before" }
            return "\(c > 0 ? "up" : "down") \(String(format: "%.1f%%", abs(c) * 100)) from \(x.metric.format(x.previous))"
        }

        var tone = "A steady \(period.rawValue)."
        if let c = sales.change, c > 0.15 { tone = "A strong \(period.rawValue) for revenue." }
        else if let c = sales.change, c < -0.15 { tone = "A softer \(period.rawValue) for revenue." }
        else if let c = dl.change, c > 0.15 { tone = "A busy \(period.rawValue) for downloads." }
        let sold = sales.value > 0 || sales.previous > 0
        var summary = "\(tone) Downloads were \(dl.metric.format(dl.value)), \(change(dl))"
            + (sold ? ", and sales reached \(sales.metric.format(sales.value)), \(change(sales))." : ".")
        if let ds = dl.change, let ss = sales.change, abs(ds) < 0.05, ss > 0.05 {
            summary += " With downloads nearly unchanged, the growth came from what people bought rather than from more visitors."
        }

        let imp = store.total(app, .impressions, from: start, to: end), impPrev = store.total(app, .impressions, from: prevStart, to: prevEnd)
        let views = store.total(app, .pageViews, from: start, to: end)
        let first = store.total(app, .firstDownloads, from: start, to: end), redl = store.total(app, .redownloads, from: start, to: end)
        let ttr = store.total(app, .ttr, from: start, to: end)
        var sections = [Report.Section(heading: "Downloads & visibility", paragraphs: !analytics ? [
            "Downloads were \(dl.metric.format(dl.value)), \(change(dl)). Impressions, product page views and first-time downloads arrive with Apple's first analytics report.",
        ] : [
            "Impressions were \(Metric.impressions.format(imp))\(impPrev > 0 ? String(format: " (%@%.1f%%)", imp >= impPrev ? "+" : "−", abs(imp / impPrev - 1) * 100) : ""), product page views \(Metric.pageViews.format(views)). Page conversion finished at \(cr.metric.format(cr.value)) and tap-through at \(Metric.ttr.format(ttr)).",
            "First-time downloads: \(Metric.firstDownloads.format(first)). Redownloads: \(Metric.redownloads.format(redl)).",
        ])]
        let proceeds = store.total(app, .proceeds, from: start, to: end)
        sections.append(.init(heading: "Sales & subscriptions", paragraphs: !sold && subs.value == 0 ? ["No sales or subscriptions this \(period.rawValue)."] : [
            "Proceeds were \(Metric.proceeds.format(proceeds)) on \(sales.metric.format(sales.value)) of sales."
                + (subs.value > 0 || subs.previous > 0 ? " Active subscriptions ended at \(Metric.activeSubs.format(subs.value)), \(change(subs))." : ""),
        ]))
        let perK = first > 0 ? ratings.value / first * 1000 : 0
        sections.append(.init(heading: "Ratings", paragraphs: ratings.value == 0 && ratings.previous == 0 ? ["No new ratings this \(period.rawValue)."] : [
            "\(Int(ratings.value)) new rating\(Int(ratings.value) == 1 ? "" : "s"), \(change(ratings))."
                + (first > 0 && ratings.value > 0 ? " That is \(String(format: "%.1f", perK)) ratings per 1,000 first-time downloads." : ""),
        ]))
        let terr = store.byTerritory(app, .downloads, from: start, to: end)
        let tot = terr.values.reduce(0, +)
        if tot > 0 {
            let top = terr.sorted { $0.value > $1.value }.prefix(5)
                .map { "\(Territories.name($0.key)) \(String(format: "%.1f%%", $0.value / tot * 100))" }
            sections.append(.init(heading: "Where downloads came from", paragraphs: ["Top markets: " + top.joined(separator: ", ") + "."]))
        }
        let releases = store.versions(app).filter { $0.day >= start && $0.day <= end }
        if !releases.isEmpty {
            sections.append(.init(heading: "Releases", paragraphs: releases.map { "Version \($0.version) shipped on \(Day.date($0.day).formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US"))))\($0.title.isEmpty ? "" : " — " + $0.title)." }))
        }
        return Report(appName: name, period: period, start: start, end: end, periodLabel: Self.label(period, start, end),
                      kpis: k, headline: headline, hasAnalytics: analytics, summary: summary, sections: sections)
    }

    static func label(_ p: ReportPeriod, _ start: String, _ end: String) -> String {
        let s = Day.date(start), e = Day.date(end), en = Locale(identifier: "en_US")
        switch p {
        case .week:
            let sameMonth = start.prefix(7) == end.prefix(7)
            return "\(s.formatted(.dateTime.month(.abbreviated).day().locale(en))) – \(sameMonth ? e.formatted(.dateTime.day().locale(en)) : e.formatted(.dateTime.month(.abbreviated).day().locale(en))), \(e.formatted(.dateTime.year().locale(en)))"
        case .month: return s.formatted(.dateTime.month(.wide).year().locale(en))
        case .year: return s.formatted(.dateTime.year().locale(en))
        }
    }
}
