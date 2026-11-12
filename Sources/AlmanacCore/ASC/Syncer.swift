import Foundation

/// Pulls everything from App Store Connect into the local store.
/// Each step is independent: one failing (e.g. no analytics access) doesn't stop the others.
public struct Syncer: Sendable {
    public let client: ASCClient
    public let store: Store
    public var salesDays = 365

    public init(client: ASCClient, store: Store) { self.client = client; self.store = store }

    public struct StepError: Sendable { public var step: String; public var message: String }

    public func syncAll(progress: @Sendable (String) -> Void = { _ in }) async -> [StepError] {
        var errors: [StepError] = []
        func attempt(_ step: String, _ body: () async throws -> Void) async {
            progress(step)
            do { try await body() } catch { errors.append(StepError(step: step, message: error.localizedDescription)) }
        }

        var apps: [(AppRecord, String)] = []  // (app, sku)
        await attempt("Apps") { apps = try await syncApps() }
        let fx = await ExchangeRates.load()
        if !client.credentials.vendorNumber.isEmpty {
            await attempt("Sales") { try await syncSales(apps: apps, fx: fx) }
            await attempt("Subscriptions") { try await syncSubscriptions(apps: apps.map(\.0)) }
        } else {
            errors.append(StepError(step: "Sales", message: "Add your vendor number in Settings to import sales."))
        }
        for (app, _) in apps {
            await attempt("Analytics · \(app.name)") { try await syncAnalytics(app: app.id) }
            await attempt("Reviews · \(app.name)") { try await syncReviews(app: app.id) }
            await attempt("Listing · \(app.name)") { try await syncListing(app: app.id) }
            await attempt("Ratings · \(app.name)") { try await syncRatings(app: app.id) }
        }
        store.setMeta("last_sync", ISO8601DateFormatter().string(from: Date()))
        return errors
    }

    // MARK: apps

    func syncApps() async throws -> [(AppRecord, String)] {
        let (data, _) = try await client.all("v1/apps", query: ["limit": "200", "fields[apps]": "name,bundleId,sku"])
        return try data.map { a in
            let hue = Double(abs(a.id.hashValue) % 360) / 360
            let rec = AppRecord(id: a.id, name: a.attr("name"), bundleId: a.attr("bundleId"), hue: hue)
            try store.upsert(app: rec)
            return (rec, a.attr("sku"))
        }
    }

    // MARK: sales (daily summary reports, one request per day)

    func syncSales(apps: [(AppRecord, String)], fx: ExchangeRates) async throws {
        let bySku = Dictionary(apps.map { ($0.1, $0.0.id) }, uniquingKeysWith: { a, _ in a })
        let byId = Set(apps.map(\.0.id))
        let yesterday = Day.add(-1, to: Day.today())
        let done = Set((store.meta("sales_days") ?? "").split(separator: ",").map(String.init))
        var imported = done
        for offset in 0..<salesDays {
            let day = Day.add(-offset, to: yesterday)
            // Re-fetch the last 3 days: Apple sometimes publishes late.
            if done.contains(day) && offset > 2 { continue }
            let data: Data
            do {
                data = try await client.request("v1/salesReports", query: [
                    "filter[frequency]": "DAILY", "filter[reportType]": "SALES", "filter[reportSubType]": "SUMMARY",
                    "filter[vendorNumber]": client.credentials.vendorNumber, "filter[reportDate]": day, "filter[version]": "1_1",
                ])
            } catch ASCError.notFound { imported.insert(day); continue } // no sales that day, or not published yet
            let rows = parseDelimited(String(decoding: try data.gunzipped(), as: UTF8.self), separator: "\t")
            var sales: [String: [String: Double]] = [:], proceeds: [String: [String: Double]] = [:]
            for r in rows {
                let appleId = r["Apple Identifier"] ?? ""
                let app = byId.contains(appleId) ? appleId : bySku[r["Parent Identifier"] ?? ""]
                guard let app else { continue }
                let units = Double(r["Units"] ?? "") ?? 0
                let country = r["Country Code"] ?? ""
                let price = fx.toUSD(Double(r["Customer Price"] ?? "") ?? 0, r["Customer Currency"] ?? "USD")
                let proc = fx.toUSD(Double(r["Developer Proceeds"] ?? "") ?? 0, r["Currency of Proceeds"] ?? "USD")
                sales[app, default: [:]][country, default: 0] += units * price
                proceeds[app, default: [:]][country, default: 0] += units * proc
            }
            var samples: [Store.Sample] = []
            for app in byId {
                let s = sales[app] ?? [:], p = proceeds[app] ?? [:]
                samples.append(.init(app, day, .sales, "", s.values.reduce(0, +)))
                samples.append(.init(app, day, .proceeds, "", p.values.reduce(0, +)))
                for (c, v) in s { samples.append(.init(app, day, .sales, c, v)) }
            }
            try store.write(samples)
            imported.insert(day)
        }
        store.setMeta("sales_days", imported.sorted().suffix(400).joined(separator: ","))
    }

    func syncSubscriptions(apps: [AppRecord]) async throws {
        let ids = Set(apps.map(\.id))
        for offset in 1...3 {
            let day = Day.add(-offset, to: Day.today())
            guard let data = try? await client.request("v1/salesReports", query: [
                "filter[frequency]": "DAILY", "filter[reportType]": "SUBSCRIPTION", "filter[reportSubType]": "SUMMARY",
                "filter[vendorNumber]": client.credentials.vendorNumber, "filter[reportDate]": day, "filter[version]": "1_3",
            ]) else { continue }
            var active: [String: Double] = [:]
            for r in parseDelimited(String(decoding: try data.gunzipped(), as: UTF8.self), separator: "\t") {
                guard let app = r["App Apple ID"], ids.contains(app) else { continue }
                active[app, default: 0] += ["Active Standard Price Subscriptions", "Active Pay Up Front Introductory Offer Subscriptions",
                                            "Active Pay As You Go Introductory Offer Subscriptions"]
                    .reduce(0) { $0 + (Double(r[$1] ?? "") ?? 0) }
            }
            try store.write(active.map { .init($0.key, day, .activeSubs, "", $0.value) })
        }
    }

    // MARK: analytics reports

    private static let reports: [(category: String, name: String)] = [
        ("APP_STORE_ENGAGEMENT", "App Store Discovery and Engagement Standard"),
        ("COMMERCE", "App Downloads Standard"),
        ("APP_USAGE", "App Sessions Standard"),
        ("APP_USAGE", "App Crashes"),
    ]

    func syncAnalytics(app: String) async throws {
        let requests = try await client.json("v1/apps/\(app)/analyticsReportRequests", query: ["filter[accessType]": "ONGOING"])
        var requestId = (requests["data"] as? [JSON])?.first?.id
        if requestId == nil {
            let created = try await client.json("v1/analyticsReportRequests", method: "POST", body: ["data": [
                "type": "analyticsReportRequests", "attributes": ["accessType": "ONGOING"],
                "relationships": ["app": ["data": ["type": "apps", "id": app]]],
            ]])
            requestId = (created["data"] as? JSON)?.id
            return // Apple needs a day or two to generate the first reports.
        }
        guard let requestId else { return }
        let imported = Set((store.meta("analytics_instances_\(app)") ?? "").split(separator: ",").map(String.init))
        var newlyImported: [String] = []

        for spec in Self.reports {
            let reports = try await client.all("v1/analyticsReportRequests/\(requestId)/reports", query: ["filter[category]": spec.category]).data
            guard let report = reports.first(where: { $0.attr("name") == spec.name }) else { continue }
            let instances = try await client.all("v1/analyticsReports/\(report.id)/instances", query: ["filter[granularity]": "DAILY", "limit": "200"], maxPages: 3).data
            for inst in instances where !imported.contains(inst.id) {
                let segments = try await client.all("v1/analyticsReportInstances/\(inst.id)/segments").data
                var acc: [String: Double] = [:] // "day|metric|territory"
                for seg in segments {
                    guard let url = URL(string: seg.attr("url")) else { continue }
                    let (raw, _) = try await URLSession.shared.data(from: url) // presigned, no auth header
                    let rows = parseDelimited(String(decoding: try raw.gunzipped(), as: UTF8.self), separator: "\t")
                    for r in rows { Self.accumulate(r, report: spec.name, into: &acc) }
                }
                try store.write(acc.map { k, v in
                    let p = k.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    return Store.Sample(app, p[0], Metric(rawValue: p[1])!, p[2], v)
                })
                newlyImported.append(inst.id)
            }
        }
        store.setMeta("analytics_instances_\(app)", (Array(imported) + newlyImported).suffix(2000).joined(separator: ","))
    }

    /// Maps one analytics CSV row to metrics. Column names follow Apple's report docs;
    /// anything unexpected is skipped rather than guessed.
    static func accumulate(_ r: [String: String], report: String, into acc: inout [String: Double]) {
        guard let day = r["Date"], !day.isEmpty else { return }
        let territory = r["Territory"] ?? ""
        let count = Double(r["Counts"] ?? r["Count"] ?? "") ?? 0
        func add(_ m: Metric, _ v: Double, territorial: Bool = true) {
            acc["\(day)|\(m.rawValue)|", default: 0] += v
            if territorial && !territory.isEmpty { acc["\(day)|\(m.rawValue)|\(territory)", default: 0] += v }
        }
        switch report {
        case "App Store Discovery and Engagement Standard":
            let event = (r["Event"] ?? "").lowercased()
            let source = (r["Source Type"] ?? "").lowercased()
            if event.contains("impression") {
                add(.impressions, count)
                add(.uniqueImpressions, Double(r["Unique Counts"] ?? "") ?? 0, territorial: false) // ponytail: unique counts summed across rows overcount slightly
                if source.contains("browse") { add(.browseImpressions, count, territorial: false) }
                if source.contains("search") { add(.searchImpressions, count, territorial: false) }
            } else if event.contains("page view") {
                add(.pageViews, count)
            }
        case "App Downloads Standard":
            let type = (r["Download Type"] ?? "").lowercased()
            if type.contains("first") { add(.firstDownloads, count) }
            else if type.contains("redownload") { add(.redownloads, count) }
        case "App Sessions Standard":
            add(.sessions, Double(r["Sessions"] ?? "") ?? count, territorial: false)
        case "App Crashes":
            add(.crashes, Double(r["Crashes"] ?? "") ?? count, territorial: false)
        default: break
        }
    }

    // MARK: reviews

    func syncReviews(app: String) async throws {
        let (data, included) = try await client.all("v1/apps/\(app)/customerReviews",
                                                    query: ["sort": "-createdDate", "limit": "200", "include": "response"], maxPages: 5)
        let responses = Dictionary(included.filter { ($0["type"] as? String) == "customerReviewResponses" }.map { ($0.id, $0.attr("responseBody")) },
                                   uniquingKeysWith: { a, _ in a })
        for r in data {
            let a = r.attrs
            try store.upsert(review: Review(
                id: r.id, appId: app, rating: a["rating"] as? Int ?? 0, title: r.attr("title"), body: r.attr("body"),
                reviewer: r.attr("reviewerNickname"), territory: Territories.alpha2(r.attr("territory")),
                created: String(r.attr("createdDate").prefix(10)), response: r.rel("response").flatMap { responses[$0] }))
        }
    }

    public func reply(to reviewId: String, _ text: String) async throws {
        _ = try await client.json("v1/customerReviewResponses", method: "POST", body: ["data": [
            "type": "customerReviewResponses", "attributes": ["responseBody": text],
            "relationships": ["review": ["data": ["type": "customerReviews", "id": reviewId]]],
        ]])
        try store.setResponse(review: reviewId, text)
    }

    // MARK: listing

    func syncListing(app: String) async throws {
        var byLocale: [String: ListingLocale] = [:]
        let versions = try await client.all("v1/apps/\(app)/appStoreVersions", query: ["limit": "50"], maxPages: 1).data
            .sorted { $0.attr("createdDate") > $1.attr("createdDate") }
        for v in versions {
            // ponytail: createdDate approximates the release day; good enough for chart markers
            try store.upsert(version: VersionMark(day: String(v.attr("createdDate").prefix(10)), version: v.attr("versionString"), title: ""), app: app)
        }
        if let latest = versions.first {
            for l in try await client.all("v1/appStoreVersions/\(latest.id)/appStoreVersionLocalizations").data {
                byLocale[l.attr("locale")] = ListingLocale(appId: app, locale: l.attr("locale"), name: "", subtitle: "",
                    keywords: l.attr("keywords"), promoText: l.attr("promotionalText"), description: l.attr("description"), versionLocalizationId: l.id)
            }
        }
        let infos = try await client.all("v1/apps/\(app)/appInfos").data
        // The editable appInfo (if a version is in preparation) comes first; fall back to the live one.
        if let info = infos.first {
            for l in try await client.all("v1/appInfos/\(info.id)/appInfoLocalizations").data {
                let loc = l.attr("locale")
                var entry = byLocale[loc] ?? ListingLocale(appId: app, locale: loc, name: "", subtitle: "", keywords: "", promoText: "", description: "")
                entry.name = l.attr("name"); entry.subtitle = l.attr("subtitle"); entry.infoLocalizationId = l.id
                byLocale[loc] = entry
            }
        }
        for l in byLocale.values { try store.upsert(listing: l) }
    }

    public func updateKeywords(_ listing: ListingLocale, keywords: String) async throws {
        guard let id = listing.versionLocalizationId else { throw ASCError.decoding("missing localization id") }
        _ = try await client.json("v1/appStoreVersionLocalizations/\(id)", method: "PATCH", body: ["data": [
            "type": "appStoreVersionLocalizations", "id": id, "attributes": ["keywords": keywords],
        ]])
        var l = listing; l.keywords = keywords
        try store.upsert(listing: l)
    }

    // MARK: ratings + icon (public iTunes lookup; no auth)

    func syncRatings(app: String) async throws {
        // ponytail: US storefront only. Summing every storefront means ~175 lookups per app.
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://itunes.apple.com/lookup?id=\(app)&country=us")!)
        guard let r = ((try JSONSerialization.jsonObject(with: data) as? JSON)?["results"] as? [JSON])?.first else { return }
        if let count = r["userRatingCount"] as? Int { try store.write([.init(app, Day.today(), .ratingsTotal, "", Double(count))]) }
        if let icon = r["artworkUrl100"] as? String { store.setMeta("icon_\(app)", icon) }
    }
}

/// ECB reference rates, EUR-based. Free, no key.
public struct ExchangeRates: Sendable {
    var perEUR: [String: Double] = ["EUR": 1, "USD": 1.08] // fallback if the feed is unreachable

    public func toUSD(_ amount: Double, _ currency: String) -> Double {
        guard amount != 0, let r = perEUR[currency], let usd = perEUR["USD"] else { return currency == "USD" ? amount : 0 }
        return amount / r * usd
    }

    public static func load() async -> ExchangeRates {
        var fx = ExchangeRates()
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!) else { return fx }
        let xml = String(decoding: data, as: UTF8.self)
        let re = #/currency='([A-Z]{3})' rate='([0-9.]+)'/#
        for m in xml.matches(of: re) { fx.perEUR[String(m.1)] = Double(m.2) }
        return fx
    }
}
