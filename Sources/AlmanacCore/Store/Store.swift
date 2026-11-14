import Foundation

/// All persistence. Plain SQLite: one row per (app, day, metric, territory).
/// Territory "" is the worldwide total.
public final class Store: @unchecked Sendable {
    public let db: DB

    public static var defaultPath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Almanac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("almanac.sqlite").path
    }

    public init(path: String = Store.defaultPath) throws {
        db = try DB(path: path)
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
        """)
    }

    // MARK: apps

    public func upsert(app: AppRecord) throws {
        try db.query("INSERT INTO apps VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, bundle_id=excluded.bundle_id",
                     [app.id, app.name, app.bundleId, app.hue])
    }

    public func apps() -> [AppRecord] {
        ((try? db.query("SELECT id,name,bundle_id,hue FROM apps ORDER BY name")) ?? [])
            .map { AppRecord(id: $0.s(0), name: $0.s(1), bundleId: $0.s(2), hue: $0.d(3)) }
    }

    public func removeAll() throws {
        try db.exec("DELETE FROM apps; DELETE FROM daily; DELETE FROM versions; DELETE FROM reviews; DELETE FROM listing; DELETE FROM insights; DELETE FROM meta;")
    }

    // MARK: daily series

    public struct Sample: Sendable {
        public var app: String, day: String, metric: Metric, territory: String, value: Double
        public init(_ app: String, _ day: String, _ metric: Metric, _ territory: String = "", _ value: Double) {
            self.app = app; self.day = day; self.metric = metric; self.territory = territory; self.value = value
        }
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
            return combine(raw(app, .pageViews, territory, from, to), raw(app, .impressions, territory, from, to)) { $1 > 0 ? $0 / $1 : 0 }
        case .pageCR:
            // Apple's definition: downloads ÷ impressions. Not ÷ page views: "Get" from search skips the page, so that goes past 100 %.
            let dl = series(app, .downloads, territory: territory, from: from, to: to)
            return combine(dl, raw(app, .impressions, territory, from, to)) { $1 > 0 ? $0 / $1 : 0 }
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
            let rows = (try? db.query("SELECT territory, SUM(value) FROM daily WHERE app_id=? AND metric=? AND territory<>'' AND day BETWEEN ? AND ? GROUP BY territory",
                                      [app, m.rawValue, from, to])) ?? []
            for r in rows { out[r.s(0), default: 0] += r.d(1) }
        }
        return out
    }

    public func lastDay(_ app: String) -> String? {
        (try? db.query("SELECT MAX(day) FROM daily WHERE app_id=? AND metric IN ('impressions','first_downloads','sales')", [app]))?.first?.opt(0)
    }

    public func lastDay(_ app: String, _ metric: Metric) -> String? {
        (try? db.query("SELECT MAX(day) FROM daily WHERE app_id=? AND metric=? AND territory=''", [app, metric.rawValue]))?.first?.opt(0)
    }

    private func raw(_ app: String, _ m: Metric, _ territory: String, _ from: String, _ to: String) -> [Point] {
        ((try? db.query("SELECT day, value FROM daily WHERE app_id=? AND metric=? AND territory=? AND day BETWEEN ? AND ? ORDER BY day",
                        [app, m.rawValue, territory, from, to])) ?? [])
            .map { Point(day: $0.s(0), value: $0.d(1)) }
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

    // MARK: reviews

    public func upsert(review r: Review) throws {
        try db.query("INSERT OR REPLACE INTO reviews VALUES(?,?,?,?,?,?,?,?,?)",
                     [r.id, r.appId, r.rating, r.title, r.body, r.reviewer, r.territory, r.created, r.response])
    }

    public func reviews(_ app: String) -> [Review] {
        ((try? db.query("SELECT id,app_id,rating,title,body,reviewer,territory,created,response FROM reviews WHERE app_id=? ORDER BY created DESC", [app])) ?? [])
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
        let sql = "SELECT json, dismissed FROM insights WHERE app_id=?" + (includeDismissed ? "" : " AND dismissed=0") + " ORDER BY day DESC"
        return ((try? db.query(sql, [app])) ?? []).compactMap { r in
            guard var i = try? dec.decode(Insight.self, from: Data(r.s(0).utf8)) else { return nil }
            i.dismissed = r.i(1) == 1
            return i
        }
    }

    public func dismiss(insight id: String) throws { try db.query("UPDATE insights SET dismissed=1 WHERE id=?", [id]) }
    public func restoreDismissed(_ app: String) throws { try db.query("UPDATE insights SET dismissed=0 WHERE app_id=?", [app]) }

    // MARK: meta

    public func meta(_ key: String) -> String? { (try? db.query("SELECT value FROM meta WHERE key=?", [key]))?.first?.opt(0) }
    public func setMeta(_ key: String, _ value: String) { try? db.query("INSERT OR REPLACE INTO meta VALUES(?,?)", [key, value]) }
}
