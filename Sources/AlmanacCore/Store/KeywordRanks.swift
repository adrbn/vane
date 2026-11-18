import Foundation

/// Where an app shows up when someone searches one of its keywords, from Apple's public search API (top 200, iPhone and iPad apps).
/// Close to the App Store's own order but not identical: Apple personalizes the real one.
public struct KeywordRank: Hashable, Sendable {
    public var term: String, country: String, day: String
    /// 1-based position, 0 when the app isn't in the first 200 results.
    public var rank: Int
    /// The same keyword and country on the previous check, if any.
    public var previous: Int?
}

public enum KeywordRanks {
    public static let depth = 200

    /// The keywords field, split as the App Store reads it.
    public static func terms(_ keywords: String) -> [String] {
        var seen = Set<String>()
        return keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 1-based position of `app` in an iTunes search response, 0 when absent.
    public static func rank(of app: String, in data: Data) -> Int {
        let results = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["results"] as? [[String: Any]] ?? []
        return (results.firstIndex { "\($0["trackId"] ?? "")" == app } ?? -1) + 1
    }
}

extension Store {
    public func save(ranks: [KeywordRank], app: String) throws {
        try db.insertMany("INSERT OR REPLACE INTO ranks VALUES(?,?,?,?,?)", ranks.map { [app, $0.day, $0.country, $0.term, Double($0.rank)] })
    }

    /// The latest check of each keyword and country, with the check before it.
    public func ranks(_ app: String) -> [KeywordRank] {
        let rows = (try? db.query("""
            SELECT term, country, day, rank,
                   (SELECT r2.rank FROM ranks r2 WHERE r2.app_id=r.app_id AND r2.term=r.term AND r2.country=r.country AND r2.day<r.day ORDER BY r2.day DESC LIMIT 1)
            FROM ranks r WHERE app_id=? AND day=(SELECT MAX(day) FROM ranks WHERE app_id=?) ORDER BY term, country
            """, [app, app])) ?? []
        return rows.map { KeywordRank(term: $0.s(0), country: $0.s(1), day: $0.s(2), rank: $0.i(3), previous: $0.values[4] == nil ? nil : $0.i(4)) }
    }
}

extension Syncer {
    /// Once a day: the primary listing's keywords in the app's three biggest countries by first-time downloads (else the US).
    func syncRanks(app: String) async throws {
        let today = Day.today()
        guard store.meta("ranks_day_\(app)") != today else { return }
        let listing = store.listing(app)
        guard let primary = listing.first(where: { $0.locale == "en-US" }) ?? listing.first else { return }
        let terms = KeywordRanks.terms(primary.keywords)
        guard !terms.isEmpty else { return }
        let top = store.byTerritory(app, .firstDownloads, from: Day.add(-90, to: today), to: today)
            .sorted { $0.value > $1.value }.prefix(3).map { $0.key.lowercased() }
        var out: [KeywordRank] = []
        for country in top.isEmpty ? ["us"] : top {
            for term in terms {
                var q = URLComponents(string: "https://itunes.apple.com/search")!
                q.queryItems = [.init(name: "term", value: term), .init(name: "country", value: country),
                                .init(name: "entity", value: "software"), .init(name: "limit", value: "\(KeywordRanks.depth)")]
                // Apple throttles past about 20 searches a minute: one retry after a pause before giving up.
                var data = Data()
                for attempt in 0..<2 {
                    let (d, response) = try await URLSession.shared.data(from: q.url!)
                    if (response as? HTTPURLResponse)?.statusCode == 200 { data = d; break }
                    if attempt == 1 { throw URLError(.badServerResponse) }
                    try await Task.sleep(for: .seconds(30))
                }
                out.append(KeywordRank(term: term, country: country, day: today, rank: KeywordRanks.rank(of: app, in: data)))
                // ponytail: fixed pause, 15 searches a minute; a few dozen keywords per app take a few minutes.
                try await Task.sleep(for: .seconds(4))
            }
        }
        try store.save(ranks: out, app: app)
        store.setMeta("ranks_day_\(app)", today)
    }
}
