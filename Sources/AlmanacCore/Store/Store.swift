import Foundation

/// All persistence. Plain SQLite: one row per (app, day, metric, territory).
/// Territory "" is the worldwide total.
public final class Store: @unchecked Sendable {
    public let db: DB
    public let path: String

    public static var defaultPath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Almanac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("almanac.sqlite").path
    }

    public init(path: String = Store.defaultPath) throws {
        db = try DB(path: path)
        self.path = path
        try db.exec("""
        CREATE TABLE IF NOT EXISTS apps(id TEXT PRIMARY KEY, name TEXT, bundle_id TEXT, hue REAL);
        CREATE TABLE IF NOT EXISTS daily(app_id TEXT, day TEXT, metric TEXT, territory TEXT, value REAL,
            PRIMARY KEY(app_id, metric, territory, day));
        CREATE TABLE IF NOT EXISTS versions(app_id TEXT, day TEXT, version TEXT, title TEXT, PRIMARY KEY(app_id, version));
        CREATE TABLE IF NOT EXISTS reviews(id TEXT PRIMARY KEY, app_id TEXT, rating INTEGER, title TEXT, body TEXT,
            reviewer TEXT, territory TEXT, created TEXT, response TEXT);
        CREATE TABLE IF NOT EXISTS listing(app_id TEXT, locale TEXT, name TEXT, subtitle TEXT, keywords TEXT, promo TEXT,
            description TEXT, version_loc_id TEXT, info_loc_id TEXT, PRIMARY KEY(app_id, locale));
        CREATE TABLE IF NOT EXISTS insights(id TEXT PRIMARY KEY, app_id TEXT, day TEXT, json TEXT, dismissed INTEGER DEFAULT 0,
            notified INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY, app_id TEXT, day TEXT, title TEXT);
        CREATE TABLE IF NOT EXISTS sources(app_id TEXT, report TEXT, day TEXT, territory TEXT, download_type TEXT, source_type TEXT,
            source_info TEXT, value REAL, PRIMARY KEY(app_id, report, day, territory, download_type, source_type, source_info));
        CREATE TABLE IF NOT EXISTS ranks(app_id TEXT, day TEXT, country TEXT, term TEXT, rank INTEGER, PRIMARY KEY(app_id, day, country, term));
        """)
    }

    // MARK: apps

    /// "*" is every app, "group:<name>" a saved group, anything else one app. As a JSON array for `json_each(?)`.
    public static let allApps = "*"
    public func appIds(_ app: String) -> [String] {
        if app == Self.allApps { return apps().map(\.id) }
        if app.hasPrefix("group:") { return groups().first { "group:" + $0.name == app }?.ids ?? [] }
        return [app]
    }

    /// "All apps", a group's name, or the app's name.
    public func displayName(_ app: String) -> String? {
        if app == Self.allApps { return String(localized: "All apps") }
        if app.hasPrefix("group:") { return String(app.dropFirst(6)) }
        return apps().first { $0.id == app }?.name
    }

    public static func isAggregate(_ app: String) -> Bool { app == allApps || app.hasPrefix("group:") }

    func scope(_ app: String) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: appIds(app))) ?? Data("[]".utf8), as: UTF8.self)
    }

    public struct AppGroup: Codable, Hashable, Sendable, Identifiable {
        public var name: String
        public var ids: [String]
        public var id: String { "group:" + name }
        public init(name: String, ids: [String]) { self.name = name; self.ids = ids }
    }

    /// Named sets of apps ("Pro + Lite"), shown together like one app.
    public func groups() -> [AppGroup] {
        (meta("app_groups").flatMap { try? JSONDecoder().decode([AppGroup].self, from: Data($0.utf8)) } ?? []).sorted { $0.name < $1.name }
    }

    public func setGroups(_ g: [AppGroup]) {
        setMeta("app_groups", String(decoding: (try? JSONEncoder().encode(g)) ?? Data("[]".utf8), as: UTF8.self))
    }

    public func upsert(app: AppRecord) throws {
        try db.query("INSERT INTO apps VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, bundle_id=excluded.bundle_id",
                     [app.id, app.name, app.bundleId, app.hue])
    }

    public func apps() -> [AppRecord] {
        ((try? db.query("SELECT id,name,bundle_id,hue FROM apps ORDER BY name")) ?? [])
            .map { AppRecord(id: $0.s(0), name: $0.s(1), bundleId: $0.s(2), hue: $0.d(3)) }
    }

    public func removeAll() throws {
        try db.exec("DELETE FROM apps; DELETE FROM daily; DELETE FROM versions; DELETE FROM reviews; DELETE FROM listing; DELETE FROM insights; DELETE FROM meta; DELETE FROM events;")
    }

    // MARK: daily series

    public struct Sample: Sendable {
        public var app: String, day: String, metric: Metric, territory: String, value: Double
        public init(_ app: String, _ day: String, _ metric: Metric, _ territory: String = "", _ value: Double) {
            self.app = app; self.day = day; self.metric = metric; self.territory = territory; self.value = value
        }
    }

    /// Downloads split by where they came from (App Store search, browse, web or app referrer).
    /// report "standard": complete, per territory, no names. "detailed": names the referring site or app, but Apple drops small rows.
    /// Rows are "day|territory|download type|source type|source info" -> count.
    public func writeSources(_ app: String, report: String, _ rows: [String: Double]) throws {
        try db.insertMany("INSERT OR REPLACE INTO sources VALUES(?,?,?,?,?,?,?,?)", rows.map { k, v in
            let p = k.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return [app, report, p[0], p[1], p[2], p[3], p[4], v]
        })
    }

    public func hasSources(_ app: String, report: String) -> Bool {
        ((try? db.query("SELECT 1 FROM sources WHERE app_id=? AND report=? LIMIT 1", [app, report])) ?? []).isEmpty == false
    }

    public func write(_ samples: [Sample]) throws {
        try db.insertMany("INSERT OR REPLACE INTO daily VALUES(?,?,?,?,?)", samples.map { [$0.app, $0.day, $0.metric.rawValue, $0.territory, $0.value] })
    }

    /// Daily series; derived metrics are computed here so every screen agrees.
    public func series(_ app: String, _ metric: Metric, territory: String = "", from: String = "0000", to: String = "9999") -> [Point] {
        switch metric {
        case .downloads:
            return combine(raw(app, .firstDownloads, territory, from, to), raw(app, .redownloads, territory, from, to), +)
        case .ttr:
            return rate(raw(app, .pageViews, territory, from, to), over: raw(app, .impressions, territory, from, to))
        case .pageCR:
            // Apple's definition: downloads ÷ impressions. Not ÷ page views: "Get" from search skips the page, so that goes past 100 %.
            return rate(series(app, .downloads, territory: territory, from: from, to: to), over: raw(app, .impressions, territory, from, to))
        case .newRatings:
            let t = raw(app, .ratingsTotal, "", Day.add(-1, to: from), to)
            return zip(t, t.dropFirst()).map { Point(day: $1.day, value: max(0, $1.value - $0.value)) }
        default:
            return raw(app, metric, territory, from, to)
        }
    }

    /// Aggregate over a period: sums for flows, ratio of sums for rates, last value for gauges.
    public func total(_ app: String, _ metric: Metric, territory: String = "", from: String, to: String) -> Double {
        switch metric {
        case .ttr:
            let i = total(app, .impressions, territory: territory, from: from, to: to)
            return i > 0 ? total(app, .pageViews, territory: territory, from: from, to: to) / i : 0
        case .pageCR:
            // Only days Apple's analytics cover: downloads come from sales reports, which go back much further.
            let imp = raw(app, .impressions, territory, from, to).filter { $0.value > 0 }
            let days = Set(imp.map(\.day)), i = imp.total
            let dl = series(app, .downloads, territory: territory, from: from, to: to).filter { days.contains($0.day) }.total
            return i > 0 ? dl / i : 0
        case .activeSubs, .ratingsTotal:
            return series(app, metric, from: from, to: to).last?.value ?? 0
        default:
            return series(app, metric, territory: territory, from: from, to: to).total
        }
    }

    /// Per-territory totals for a flow metric over a period.
    public func byTerritory(_ app: String, _ metric: Metric, from: String, to: String) -> [String: Double] {
        let metrics: [Metric] = metric == .downloads ? [.firstDownloads, .redownloads] : [metric]
        var out: [String: Double] = [:]
        for m in metrics {
            let rows = (try? db.query("SELECT territory, SUM(value) FROM daily WHERE app_id IN (SELECT value FROM json_each(?)) AND metric=? AND territory<>'' AND day BETWEEN ? AND ? GROUP BY territory",
                                      [scope(app), m.rawValue, from, to])) ?? []
            for r in rows { out[r.s(0), default: 0] += r.d(1) }
        }
        return out
    }

    public func lastDay(_ app: String) -> String? {
        (try? db.query("SELECT MAX(day) FROM daily WHERE app_id IN (SELECT value FROM json_each(?)) AND metric IN ('impressions','first_downloads','sales')", [scope(app)]))?.first?.opt(0)
    }

    public func firstDay(_ app: String, _ metric: Metric) -> String? {
        (try? db.query("SELECT MIN(day) FROM daily WHERE app_id IN (SELECT value FROM json_each(?)) AND metric=? AND territory=''", [scope(app), metric.rawValue]))?.first?.opt(0)
    }

    public func lastDay(_ app: String, _ metric: Metric) -> String? {
        (try? db.query("SELECT MAX(day) FROM daily WHERE app_id IN (SELECT value FROM json_each(?)) AND metric=? AND territory=''", [scope(app), metric.rawValue]))?.first?.opt(0)
    }

    private func raw(_ app: String, _ m: Metric, _ territory: String, _ from: String, _ to: String) -> [Point] {
        ((try? db.query("SELECT day, SUM(value) FROM daily WHERE app_id IN (SELECT value FROM json_each(?)) AND metric=? AND territory=? AND day BETWEEN ? AND ? GROUP BY day ORDER BY day",
                        [scope(app), m.rawValue, territory, from, to])) ?? [])
            .map { Point(day: $0.s(0), value: $0.d(1)) }
    }

    /// Daily ratio, only on days with a denominator: a day without Apple's analytics is missing, not 0 %.
    private func rate(_ a: [Point], over b: [Point]) -> [Point] {
        let am = Dictionary(a.map { ($0.day, $0.value) }, uniquingKeysWith: { x, _ in x })
        return b.filter { $0.value > 0 }.map { Point(day: $0.day, value: (am[$0.day] ?? 0) / $0.value) }
    }

    private func combine(_ a: [Point], _ b: [Point], _ f: (Double, Double) -> Double) -> [Point] {
        let bm = Dictionary(b.map { ($0.day, $0.value) }, uniquingKeysWith: { x, _ in x })
        let days = Set(a.map(\.day)).union(bm.keys).sorted()
        let am = Dictionary(a.map { ($0.day, $0.value) }, uniquingKeysWith: { x, _ in x })
        return days.map { Point(day: $0, value: f(am[$0] ?? 0, bm[$0] ?? 0)) }
    }

    // MARK: versions

    public func upsert(version v: VersionMark, app: String) throws {
        try db.query("INSERT OR REPLACE INTO versions VALUES(?,?,?,?)", [app, v.day, v.version, v.title])
    }

    public func versions(_ app: String) -> [VersionMark] {
        ((try? db.query("SELECT day,version,title FROM versions WHERE app_id=? ORDER BY day", [app])) ?? [])
            .map { VersionMark(day: $0.s(0), version: $0.s(1), title: $0.s(2)) }
    }

    // MARK: events

    public func save(event e: AppEvent) throws { try db.query("INSERT OR REPLACE INTO events VALUES(?,?,?,?)", [e.id, e.appId, e.day, e.title]) }
    public func delete(event id: String) throws { try db.query("DELETE FROM events WHERE id=?", [id]) }

    /// This app's events plus the ones for every app.
    public func events(_ app: String) -> [AppEvent] {
        ((try? db.query("SELECT id,app_id,day,title FROM events WHERE app_id IN (SELECT value FROM json_each(?)) OR app_id='' ORDER BY day", [scope(app)])) ?? [])
            .map { AppEvent(id: $0.s(0), appId: $0.s(1), day: $0.s(2), title: $0.s(3)) }
    }

    /// Releases and events, for chart rules and chat context.
    public func marks(_ app: String) -> [VersionMark] {
        (versions(app) + events(app).map { VersionMark(day: $0.day, version: $0.title, title: "", isEvent: true) }).sorted { $0.day < $1.day }
    }

    // MARK: reviews

    public func upsert(review r: Review) throws {
        try db.query("INSERT OR REPLACE INTO reviews VALUES(?,?,?,?,?,?,?,?,?)",
                     [r.id, r.appId, r.rating, r.title, r.body, r.reviewer, r.territory, r.created, r.response])
    }

    public func reviews(_ app: String) -> [Review] {
        ((try? db.query("SELECT id,app_id,rating,title,body,reviewer,territory,created,response FROM reviews WHERE app_id IN (SELECT value FROM json_each(?)) ORDER BY created DESC", [scope(app)])) ?? [])
            .map { Review(id: $0.s(0), appId: $0.s(1), rating: $0.i(2), title: $0.s(3), body: $0.s(4), reviewer: $0.s(5), territory: $0.s(6), created: $0.s(7), response: $0.opt(8)) }
    }

    public func setResponse(review id: String, _ text: String) throws {
        try db.query("UPDATE reviews SET response=? WHERE id=?", [text, id])
    }

    // MARK: listing

    public func upsert(listing l: ListingLocale) throws {
        try db.query("INSERT OR REPLACE INTO listing VALUES(?,?,?,?,?,?,?,?,?)",
                     [l.appId, l.locale, l.name, l.subtitle, l.keywords, l.promoText, l.description, l.versionLocalizationId, l.infoLocalizationId])
    }

    public func listing(_ app: String) -> [ListingLocale] {
        ((try? db.query("SELECT app_id,locale,name,subtitle,keywords,promo,description,version_loc_id,info_loc_id FROM listing WHERE app_id=? ORDER BY locale", [app])) ?? [])
            .map { ListingLocale(appId: $0.s(0), locale: $0.s(1), name: $0.s(2), subtitle: $0.s(3), keywords: $0.s(4), promoText: $0.s(5), description: $0.s(6), versionLocalizationId: $0.opt(7), infoLocalizationId: $0.opt(8)) }
    }

    // MARK: insights

    /// Inserts new insights, refreshes content of existing ones, keeps dismissed/notified flags.
    /// Returns the insights that are new since the last run.
    @discardableResult
    public func merge(insights: [Insight]) throws -> [Insight] {
        let enc = JSONEncoder()
        var fresh: [Insight] = []
        try db.transaction {
            for i in insights {
                let exists = try !db.query("SELECT 1 FROM insights WHERE id=?", [i.id]).isEmpty
                let json = String(decoding: try enc.encode(i), as: UTF8.self)
                if exists {
                    try db.query("UPDATE insights SET json=?, day=? WHERE id=?", [json, i.day, i.id])
                } else {
                    try db.query("INSERT INTO insights(id,app_id,day,json) VALUES(?,?,?,?)", [i.id, i.appId, i.day, json])
                    fresh.append(i)
                }
            }
        }
        return fresh
    }

    public func insights(_ app: String, includeDismissed: Bool = false) -> [Insight] {
        let dec = JSONDecoder()
        let sql = "SELECT json, dismissed FROM insights WHERE app_id IN (SELECT value FROM json_each(?))" + (includeDismissed ? "" : " AND dismissed=0") + " ORDER BY day DESC"
        return ((try? db.query(sql, [scope(app)])) ?? []).compactMap { r in
            guard var i = try? dec.decode(Insight.self, from: Data(r.s(0).utf8)) else { return nil }
            i.dismissed = r.i(1) == 1
            return i
        }
    }

    /// Removes insights of `kinds` the engine no longer produces (e.g. a keyword issue that was fixed).
    public func prune(_ app: String, kinds: Set<String>, keeping ids: Set<String>) throws {
        for r in try db.query("SELECT id, json FROM insights WHERE app_id=?", [app]) where !ids.contains(r.s(0)) {
            guard let i = try? JSONDecoder().decode(Insight.self, from: Data(r.s(1).utf8)), kinds.contains(i.kind) else { continue }
            try db.query("DELETE FROM insights WHERE id=?", [r.s(0)])
        }
    }

    public func dismiss(insight id: String) throws { try db.query("UPDATE insights SET dismissed=1 WHERE id=?", [id]) }
    public func restoreDismissed(_ app: String) throws { try db.query("UPDATE insights SET dismissed=0 WHERE app_id=?", [app]) }

    // MARK: meta

    public func meta(_ key: String) -> String? { (try? db.query("SELECT value FROM meta WHERE key=?", [key]))?.first?.opt(0) }
    public func setMeta(_ key: String, _ value: String) { try? db.query("INSERT OR REPLACE INTO meta VALUES(?,?)", [key, value]) }
}
