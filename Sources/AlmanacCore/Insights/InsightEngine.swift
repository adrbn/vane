import Foundation

private let enUS = Locale.current

/// Rule-based insight detection over the local store. Deterministic, no AI:
/// every insight is a number the developer can verify on the matching chart.
public struct InsightEngine {
    let store: Store
    let app: String
    let asOf: String

    public init(store: Store, app: String, asOf: String? = nil) {
        self.store = store
        self.app = app
        self.asOf = asOf ?? store.lastDay(app) ?? Day.today()
    }

    public func run() -> [Insight] {
        let rules: [() -> [Insight]] = [
            { opt(bestDownloadDay()) }, { downloadMilestones() }, { opt(featured()) },
            { opt(rateDrop(.ttr, kind: "ttr-drop", noun: String(localized: "Tap-through rate"))) },
            { opt(rateDrop(.pageCR, kind: "cr-drop", noun: String(localized: "Conversion"))) },
            { opt(growthStreak()) }, { opt(salesSwing()) }, { opt(ratingsSlowed()) }, { opt(crashesUp()) },
            { territorySurges() }, { listingIssues() }, { opt(lowRatedReviews()) }, { opt(weekendPattern()) },
            { reportInsights() },
        ]
        return rules.flatMap { $0() }
    }

    /// Runs the rules, stores the result, drops fixed listing issues. Returns the insights that are new.
    @discardableResult
    public static func refresh(store: Store, app: String) -> [Insight] {
        let found = InsightEngine(store: store, app: app).run()
        try? store.prune(app, kinds: Insight.liveKinds, keeping: Set(found.map(\.id)))
        return (try? store.merge(insights: found)) ?? []
    }

    private func opt(_ i: Insight?) -> [Insight] { i.map { [$0] } ?? [] }
    private func id(_ kind: String, _ key: String) -> String { "\(app)|\(kind)|\(key)" }
    private func day(_ offset: Int) -> String { Day.add(offset, to: asOf) }
    private func pct(_ x: Double) -> String { String(format: "%.0f%%", abs(x) * 100) }

    // MARK: milestones

    func bestDownloadDay() -> Insight? {
        let s = store.series(app, .downloads, from: day(-240), to: asOf)
        guard s.count > 60, let last = s.last, last.day == asOf else { return nil }
        let previousBest = s.dropLast().map(\.value).max() ?? 0
        guard last.value > previousBest, previousBest > 0 else { return nil }
        let months = max(1, s.count / 30)
        return Insight(id: id("best-day", asOf), appId: app, kind: "best-day", category: .milestones,
                       title: String(localized: "Your best download day in \(months) months"),
                       body: String(localized: "You got \(Int(last.value).formatted(.number.locale(enUS))) downloads on \(Day.date(asOf).formatted(.dateTime.month(.wide).day().locale(enUS))), more than any day since \(Day.date(s[0].day).formatted(.dateTime.month(.wide).year().locale(enUS)))."),
                       day: asOf, chart: InsightChart(label: String(localized: "Daily downloads"), points: s.suffix(30).map(ChartPoint.init),
                                                      baselineLabel: String(localized: "Previous best: \(Int(previousBest).formatted(.number.locale(enUS)))"), baseline: previousBest, headline: Int(last.value).formatted(.number.locale(enUS))))
    }

    public static let downloadMarks = [1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_500_000, 5_000_000]

    func downloadMilestones() -> [Insight] {
        let s = store.series(app, .downloads)
        guard !s.isEmpty else { return [] }
        let marks = Self.downloadMarks
        var running = 0.0, out: [Insight] = []
        var next = marks.makeIterator(), target = next.next()
        for p in s {
            running += p.value
            while let t = target, running >= Double(t) {
                // Only surface recent milestones; old ones are noise after the first import.
                if Day.between(p.day, asOf) <= 30 {
                    out.append(Insight(id: id("milestone", "\(t)"), appId: app, kind: "milestone", category: .milestones,
                                       title: String(localized: "You passed \(t.formatted(.number.locale(enUS))) downloads"),
                                       body: String(localized: "Your app has had \(Int(running).formatted(.number.locale(enUS))) downloads since \(Day.date(s[0].day).formatted(.dateTime.month(.wide).year().locale(enUS))), including redownloads."),
                                       day: p.day, chart: InsightChart(label: "", points: [], headline: t.formatted(.number.locale(enUS)), isBigNumber: true)))
                }
                target = next.next()
            }
        }
        return out
    }

    func growthStreak() -> Insight? {
        let weeks = store.series(app, .downloads, from: Day.weekStart(day(-7 * 12)), to: Day.add(-1, to: Day.weekStart(asOf))).bucketed(.week)
        var streak = 0
        for (a, b) in zip(weeks, weeks.dropFirst()).reversed() { if b.value > a.value { streak += 1 } else { break } }
        guard streak >= 4, let lastWeek = weeks.last else { return nil }
        return Insight(id: id("streak", lastWeek.day), appId: app, kind: "streak", category: .milestones,
                       title: String(localized: "Downloads grew for \(streak) straight weeks"),
                       body: String(localized: "Weekly downloads increased every week for \(streak) weeks in a row."), day: Day.add(6, to: lastWeek.day),
                       chart: InsightChart(label: String(localized: "Weekly downloads"), points: weeks.suffix(streak + 1).map(ChartPoint.init), headline: Int(lastWeek.value).formatted(.number.locale(enUS))))
    }

    // MARK: discovery

    func featured() -> Insight? {
        let s = store.series(app, .browseImpressions, from: day(-37), to: asOf)
        guard s.count >= 30 else { return nil }
        let usual = median(s.dropLast(7).map(\.value))
        let recent = s.suffix(7).map(\.value).max() ?? 0
        guard usual > 20, recent > usual * 3 else { return nil }
        let peakDay = s.suffix(7).max { $0.value < $1.value }!.day
        let top = store.byTerritory(app, .impressions, from: day(-6), to: asOf)
        let base = store.byTerritory(app, .impressions, from: day(-34), to: day(-7)).mapValues { $0 / 4 }
        let lead = top.max { ($0.value - (base[$0.key] ?? 0)) < ($1.value - (base[$1.key] ?? 0)) }?.key
        return Insight(id: id("featured", Day.weekStart(peakDay)), appId: app, kind: "featured", category: .discovery,
                       title: String(localized: "Your app may be featured") + (lead.map { " " + Territories.flag($0) } ?? ""),
                       body: lead.map { String(localized: "Browse traffic is \(Int(recent / usual))× its usual level, mostly in \(Territories.name($0)). An App Store feature or chart placement would explain it.") }
                           ?? String(localized: "Browse traffic is \(Int(recent / usual))× its usual level. An App Store feature or chart placement would explain it."),
                       day: peakDay, chart: InsightChart(label: String(localized: "Daily browse impressions"), points: s.map(ChartPoint.init),
                                                         baselineLabel: String(localized: "Usual: \(Int(usual).formatted(.number.locale(enUS)))"), baseline: usual, headline: Int(recent).formatted(.number.locale(enUS))))
    }

    func listingIssues() -> [Insight] {
        var out: [Insight] = []
        for l in store.listing(app) {
            let shown = Set(words(l.name + " " + l.subtitle))
            let kws = l.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let repeated = kws.filter { k in words(k).allSatisfy(shown.contains) }
            if !repeated.isEmpty {
                let fixed = kws.filter { !repeated.contains($0) }.joined(separator: ",")
                out.append(Insight(id: id("kw-repeat", l.locale + repeated.joined()), appId: app, kind: "kw-repeat", category: .discovery,
                                   title: String(localized: "Your keywords repeat words from your name or subtitle"),
                                   body: String(localized: "\(Locale.current.localizedString(forIdentifier: l.locale) ?? l.locale): \(repeated.map { "“\($0)”" }.joined(separator: ", ")). \(repeated.count) keywords already appear in the name or subtitle, so they earn nothing in the keyword field. Free up \(repeated.joined(separator: ",").count) characters for new words."),
                                   day: asOf, needsAttention: true, action: .fixKeywords(locale: l.locale, keywords: fixed)))
            }
            let used = l.keywords.count
            if !l.keywords.isEmpty && used < 80 {
                out.append(Insight(id: id("kw-short", l.locale), appId: app, kind: "kw-short", category: .discovery,
                                   title: String(localized: "\(100 - used) keyword characters unused"),
                                   body: String(localized: "\(Locale.current.localizedString(forIdentifier: l.locale) ?? l.locale) uses \(used) of 100 characters. Every free character is a search term you aren't ranking for."),
                                   day: asOf, needsAttention: true, action: .openMetric("listing")))
            }
            if l.subtitle.isEmpty && !l.name.isEmpty {
                out.append(Insight(id: id("no-subtitle", l.locale), appId: app, kind: "no-subtitle", category: .discovery,
                                   title: String(localized: "No subtitle in \(Locale.current.localizedString(forIdentifier: l.locale) ?? l.locale)"),
                                   body: String(localized: "The subtitle is indexed for search and shown under your name. 30 free characters are going unused."),
                                   day: asOf, needsAttention: true, action: .openMetric("listing")))
            }
        }
        return out
    }

    // MARK: conversion

    func rateDrop(_ m: Metric, kind: String, noun: String) -> Insight? {
        let recent = store.total(app, m, from: day(-13), to: asOf)
        let before = store.total(app, m, from: day(-41), to: day(-14))
        guard before > 0, recent > 0, recent < before * 0.85 else { return nil }
        let weekly = store.series(app, m, from: day(-41), to: asOf).bucketed(.week, average: true)
        return Insight(id: id(kind, Day.weekStart(asOf)), appId: app, kind: kind, category: .conversion,
                       title: String(localized: "\(noun) fell \(pct(1 - recent / before))"),
                       body: m == .ttr ? String(localized: "Fewer people who saw your app tapped through to its page. Check your icon, name and first screenshots, and any Search Ads changes.")
                                       : String(localized: "Fewer people who saw your app downloaded it. Check your screenshots, price and recent ratings."),
                       day: asOf, needsAttention: true,
                       chart: InsightChart(label: m.title, points: weekly.map(ChartPoint.init), baselineLabel: String(localized: "Before: \(m.format(before))"), baseline: before,
                                           headline: m.format(recent)), action: .openMetric(m.rawValue))
    }

    // MARK: revenue

    func salesSwing() -> Insight? {
        let thisWeekStart = Day.add(-7, to: Day.weekStart(asOf))
        let a = store.total(app, .sales, from: thisWeekStart, to: Day.add(6, to: thisWeekStart))
        let b = store.total(app, .sales, from: Day.add(-7, to: thisWeekStart), to: Day.add(-1, to: thisWeekStart))
        guard b > 50, abs(a / b - 1) >= 0.2 else { return nil }
        let up = a > b
        let dl = store.total(app, .downloads, from: thisWeekStart, to: Day.add(6, to: thisWeekStart))
        let dlBefore = store.total(app, .downloads, from: Day.add(-7, to: thisWeekStart), to: Day.add(-1, to: thisWeekStart))
        let why = dlBefore > 0 && abs(dl / dlBefore - 1) < 0.08 ? String(localized: " Downloads barely moved, so the change came from what people bought.") : ""
        return Insight(id: id("sales-swing", thisWeekStart), appId: app, kind: "sales-swing", category: .revenue,
                       title: up ? String(localized: "Sales jumped \(pct(a / b - 1)) last week") : String(localized: "Sales dropped \(pct(a / b - 1)) last week"),
                       body: String(localized: "\(a.formatted(.currency(code: "USD"))) against \(b.formatted(.currency(code: "USD"))) the week before.") + why,
                       day: Day.add(6, to: thisWeekStart), needsAttention: !up,
                       chart: InsightChart(label: String(localized: "Daily sales"), points: store.series(app, .sales, from: day(-27), to: asOf).map(ChartPoint.init),
                                           headline: a.formatted(.currency(code: "USD"))), action: .openMetric("sales"))
    }

    func weekendPattern() -> Insight? {
        let s = store.series(app, .sales, from: day(-55), to: asOf)
        guard s.count >= 49, s.total > 100 else { return nil }
        var wk = [Double](repeating: 0, count: 7)
        for p in s { wk[(Day.calendar.component(.weekday, from: p.date) + 5) % 7] += p.value }
        let weekend = (wk[4] + wk[5] + wk[6]) / 3, weekday = (wk[0] + wk[1] + wk[2] + wk[3]) / 4
        guard weekday > 0, weekend > weekday * 1.25 else { return nil }
        return Insight(id: id("weekend", String(asOf.prefix(7))), appId: app, kind: "weekend", category: .revenue,
                       title: String(localized: "Weekends sell best"),
                       body: String(localized: "Friday to Sunday bring \(pct(weekend / weekday - 1)) more sales per day than the rest of the week. Time releases and promotions for Thursday."),
                       day: asOf)
    }

    // MARK: ratings

    func ratingsSlowed() -> Insight? {
        let v = store.versions(app).filter { $0.day <= day(-14) }.last
        guard let v else { return nil }
        let after = store.total(app, .newRatings, from: v.day, to: asOf), dlAfter = store.total(app, .firstDownloads, from: v.day, to: asOf)
        let before = store.total(app, .newRatings, from: Day.add(-42, to: v.day), to: Day.add(-1, to: v.day))
        let dlBefore = store.total(app, .firstDownloads, from: Day.add(-42, to: v.day), to: Day.add(-1, to: v.day))
        guard dlAfter > 200, dlBefore > 200, before > 10 else { return nil }
        let rA = after / dlAfter * 1000, rB = before / dlBefore * 1000
        guard rA < rB * 0.7 else { return nil }
        return Insight(id: id("ratings-slowed", v.version), appId: app, kind: "ratings-slowed", category: .ratings,
                       title: String(localized: "Ratings slowed after version \(v.version)"),
                       body: String(localized: "\(String(format: "%.1f", rA)) ratings per 1,000 downloads since this release, down from \(String(format: "%.1f", rB)). Check whether your rating prompt changed."),
                       day: asOf, needsAttention: true)
    }

    func lowRatedReviews() -> Insight? {
        let recent = store.reviews(app).prefix(10)
        guard recent.count == 10 else { return nil }
        let avg = Double(recent.map(\.rating).reduce(0, +)) / 10
        let unanswered = recent.filter { $0.rating <= 2 && $0.response == nil }.count
        guard avg < 3.5 || unanswered >= 3 else { return nil }
        return Insight(id: id("low-reviews", recent.first!.created), appId: app, kind: "low-reviews", category: .ratings,
                       title: avg < 3.5 ? String(localized: "Recent reviews average \(String(format: "%.1f", avg)) stars") : String(localized: "\(unanswered) unhappy reviews have no reply"),
                       body: String(localized: "A reply often turns a 1-star review into an update. \(unanswered) of your last 10 reviews are 1–2 stars without a response."),
                       day: recent.first!.created, needsAttention: true, action: .openMetric("reviews"))
    }

    // MARK: retention

    func crashesUp() -> Insight? {
        let c7 = store.total(app, .crashes, from: day(-6), to: asOf), s7 = store.total(app, .sessions, from: day(-6), to: asOf)
        let c28 = store.total(app, .crashes, from: day(-34), to: day(-7)), s28 = store.total(app, .sessions, from: day(-34), to: day(-7))
        guard s7 > 0, s28 > 0, c28 > 0 else { return nil }
        let r = (c7 / s7) / (c28 / s28)
        guard r > 1.5, c7 > 10 else { return nil }
        return Insight(id: id("crashes", Day.weekStart(asOf)), appId: app, kind: "crashes", category: .retention,
                       title: String(localized: "More devices are crashing"),
                       body: String(localized: "Crashes per session are \(String(format: "%.1f", r))× last month's rate. Check crash reports in Xcode Organizer, starting with recent releases."),
                       day: asOf, needsAttention: true,
                       chart: InsightChart(label: String(localized: "Daily crashes"), points: store.series(app, .crashes, from: day(-34), to: asOf).map(ChartPoint.init), headline: Int(c7).formatted(.number.locale(enUS))))
    }

    // MARK: markets

    func territorySurges() -> [Insight] {
        let now = store.byTerritory(app, .downloads, from: day(-6), to: asOf)
        let before = store.byTerritory(app, .downloads, from: day(-34), to: day(-7)).mapValues { $0 / 4 }
        return now.compactMap { code, v -> Insight? in
            let b = before[code] ?? 0
            guard v >= 25, v > max(b, 1) * 1.6 else { return nil }
            return Insight(id: id("surge", code + Day.weekStart(asOf)), appId: app, kind: "surge", category: .markets,
                           title: String(localized: "\(Territories.flag(code)) \(Territories.name(code)) is picking up"),
                           body: String(localized: "\(Int(v)) downloads this week, up from about \(Int(b)) a week. A localized listing for this market could compound it."),
                           day: asOf,
                           chart: InsightChart(label: String(localized: "Weekly downloads"), points: (0..<8).reversed().map { w in
                               ChartPoint(Point(day: day(-6 - 7 * w), value: store.total(app, .downloads, territory: code, from: day(-6 - 7 * w), to: day(-7 * w))))
                           }, baselineLabel: String(localized: "Usual: \(Int(b)) a week"), baseline: b, headline: Int(v).formatted(.number.locale(enUS))),
                           action: .openMetric("territories"))
        }
        .sorted { $0.title < $1.title }.prefix(3).map { $0 }
    }

    // MARK: reports

    func reportInsights() -> [Insight] {
        let lastWeek = Day.add(-7, to: Day.weekStart(Day.add(1, to: asOf)))
        guard store.total(app, .downloads, from: lastWeek, to: Day.add(6, to: lastWeek)) > 0 else { return [] }
        let r = ReportBuilder(store: store, app: app).build(.week, start: lastWeek)
        return [Insight(id: id("report-week", lastWeek), appId: app, kind: "report-week", category: .reports,
                        title: String(localized: "Weekly report: \(r.periodLabel)"), body: r.summary, day: Day.add(7, to: lastWeek),
                        action: .openReport(period: "week", start: lastWeek))]
    }

    // MARK: helpers

    private func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 }
    }

    private func median(_ xs: [Double]) -> Double {
        let s = xs.sorted(); return s.isEmpty ? 0 : s[s.count / 2]
    }
}
