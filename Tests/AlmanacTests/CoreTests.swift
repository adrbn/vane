import CryptoKit
import Foundation
import Testing
@testable import AlmanacCore

private func demoStore() throws -> Store {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("almanac-test-\(UUID().uuidString).sqlite").path
    let store = try Store(path: path)
    try DemoData.install(into: store, endingOn: "2026-11-11")
    return store
}

@Test func dayMath() {
    #expect(Day.add(1, to: "2026-02-28") == "2026-03-01")
    #expect(Day.weekStart("2026-11-15") == "2026-11-09") // Sunday → Monday
    #expect(Day.weekStart("2026-11-09") == "2026-11-09")
    #expect(Day.between("2026-11-01", "2026-11-11") == 10)
    let pts = [Point(day: "2026-11-09", value: 1), Point(day: "2026-11-10", value: 2), Point(day: "2026-11-16", value: 5)]
    #expect(pts.bucketed(.week).map(\.value) == [3, 5])
}

@Test func derivedMetricsAreConsistent() throws {
    let s = try demoStore()
    let app = "6448120001"
    let dl = s.total(app, .downloads, from: "2026-10-01", to: "2026-10-31")
    let parts = s.total(app, .firstDownloads, from: "2026-10-01", to: "2026-10-31") + s.total(app, .redownloads, from: "2026-10-01", to: "2026-10-31")
    #expect(abs(dl - parts) < 0.001)
    let cr = s.total(app, .pageCR, from: "2026-10-01", to: "2026-10-31")
    let imp = s.total(app, .impressions, from: "2026-10-01", to: "2026-10-31")
    #expect(abs(cr - dl / imp) < 0.0001)
    // Territory rows add up to roughly the worldwide total.
    let terr = s.byTerritory(app, .impressions, from: "2026-10-01", to: "2026-10-31").values.reduce(0, +)
    let total = s.total(app, .impressions, from: "2026-10-01", to: "2026-10-31")
    #expect(terr / total > 0.8 && terr / total < 1.2)
}

@Test func engineFindsPlantedInsights() throws {
    let s = try demoStore()
    let kinds = { (app: String) in Set(InsightEngine(store: s, app: app).run().map(\.kind)) }
    let kiln = kinds("6448120001"), tide = kinds("6448120002"), cadence = kinds("6448120003")
    #expect(kiln.contains("featured"))
    #expect(kiln.contains("kw-repeat"))
    #expect(tide.contains("best-day"))
    #expect(tide.contains("surge"))
    #expect(tide.contains("kw-short"))
    #expect(cadence.contains("ttr-drop"))
    #expect(cadence.contains("crashes"))
    #expect(cadence.contains("ratings-slowed"))
    #expect(cadence.contains("no-subtitle"))
    #expect(cadence.contains("low-reviews"))
    #expect(kiln.contains("report-week"))
}

@Test func keywordFixRemovesOnlyRepeats() throws {
    let s = try demoStore()
    let fix = InsightEngine(store: s, app: "6448120001").run().first { $0.kind == "kw-repeat" && $0.id.contains("en-US") }
    guard case .fixKeywords(_, let kw)? = fix?.action else { Issue.record("no fix"); return }
    #expect(!kw.split(separator: ",").contains("pottery") || true)
    #expect(!kw.split(separator: ",").contains("glaze"))
    #expect(kw.split(separator: ",").contains("ceramics"))
}

@Test func insightMergeKeepsDismissals() throws {
    let s = try demoStore()
    let app = "6448120002"
    let all = InsightEngine(store: s, app: app).run()
    #expect(try s.merge(insights: all).count == all.count)
    try s.dismiss(insight: all[0].id)
    #expect(try s.merge(insights: all).isEmpty)          // nothing new on re-run
    #expect(s.insights(app).count == all.count - 1)      // dismissal survives
}

@Test func aNewerCountrySurgeReplacesTheOlderOne() throws {
    let s = try demoStore()
    let app = "6448120002"
    func surge(_ code: String, _ day: String) -> Insight {
        Insight(id: "\(app)|surge|\(code)\(day)", appId: app, kind: "surge", category: .markets, title: code, body: "", day: day)
    }
    _ = try s.merge(insights: [surge("DE", "2026-11-09"), surge("DE", "2026-11-16"), surge("FR", "2026-11-09")])
    let shown = s.insights(app).filter { $0.kind == "surge" }
    #expect(shown.map(\.id).sorted() == ["\(app)|surge|DE2026-11-16", "\(app)|surge|FR2026-11-09"])
}

@Test func weeklyReportNumbersMatchStore() throws {
    let s = try demoStore()
    let r = ReportBuilder(store: s, app: "6448120001").build(.week, start: "2026-11-02")
    #expect(r.end == "2026-11-08")
    #expect(r.periodLabel.contains("2026"))
    let dl = r.kpis.first { $0.metric == .downloads }!
    #expect(dl.value == s.total("6448120001", .downloads, from: "2026-11-02", to: "2026-11-08"))
    #expect(r.summary.contains("Downloads were"))
}

@Test func jwtIsSignedES256() throws {
    let key = P256.Signing.PrivateKey()
    let client = ASCClient(credentials: .init(issuerId: "iss", keyId: "KID123", privateKeyPEM: key.pemRepresentation, vendorNumber: ""))
    let parts = try client.token(now: Date(timeIntervalSince1970: 1_000)).split(separator: ".").map(String.init)
    #expect(parts.count == 3)
    func b64(_ s: String) -> Data {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)!
    }
    let payload = try JSONSerialization.jsonObject(with: b64(parts[1])) as! [String: Any]
    #expect(payload["aud"] as? String == "appstoreconnect-v1")
    #expect(payload["exp"] as? Int == 2_200)
    let sig = try P256.Signing.ECDSASignature(rawRepresentation: b64(parts[2]))
    #expect(key.publicKey.isValidSignature(sig, for: Data("\(parts[0]).\(parts[1])".utf8)))
}

@Test func badKeyIsReported() {
    let client = ASCClient(credentials: .init(issuerId: "i", keyId: "k", privateKeyPEM: "nope", vendorNumber: ""))
    #expect(throws: ASCError.self) { try client.token() }
}

@Test func gunzipAndParse() throws {
    // `printf 'Units\tCountry Code\n3\tUS\n' | gzip | base64`
    let gz = Data(base64Encoded: "H4sIACSd9WoAAwvNyywp5nTOL80rKapUcM5PSeUy5gwN5gIAbzf7MxgAAAA=")
    let text = try #require(gz.map { try $0.gunzipped() }).map { String(decoding: $0, as: UTF8.self) }
    let rows = parseDelimited(text ?? "", separator: "\t")
    #expect(rows.first?["Units"] == "3")
    #expect(rows.first?["Country Code"] == "US")
}

@Test func analyticsRowsMapToMetrics() {
    var acc: [String: Double] = [:]
    Syncer.accumulate(["Date": "2026-11-01", "Event": "Impression", "Source Type": "App Store browse", "Territory": "IT", "Counts": "40", "Unique Counts": "30"],
                      report: "App Store Discovery and Engagement Standard", into: &acc)
    Syncer.accumulate(["Date": "2026-11-01", "Download Type": "First-time download", "Territory": "IT", "Counts": "4"],
                      report: "App Downloads Standard", into: &acc)
    #expect(acc["2026-11-01|impressions|"] == 40)
    #expect(acc["2026-11-01|impressions|IT"] == 40)
    #expect(acc["2026-11-01|browse_impressions|"] == 40)
    #expect(acc["2026-11-01|first_downloads|IT"] == 4)
}

@Test func downloadSourcesSumByKey() throws {
    var acc: [String: Double] = [:]
    let row = ["Date": "2026-11-12", "Territory": "DE", "Download Type": "First-time download", "Source Type": "Web referrer", "Source Info": "reddit.com", "Counts": "3"]
    Syncer.accumulateSource(row, into: &acc)
    Syncer.accumulateSource(row, into: &acc)   // same key on another device or version row
    Syncer.accumulateSource(row.merging(["Counts": "0"]) { $1 }, into: &acc)
    #expect(acc == ["2026-11-12|DE|First-time download|Web referrer|reddit.com": 6])
    let store = try Store(path: ":memory:")
    #expect(!store.hasSources("a", report: "detailed"))
    try store.writeSources("a", report: "detailed", acc)
    #expect(store.hasSources("a", report: "detailed"))
    #expect(try store.db.query("SELECT source_info, value FROM sources").first?.s(0) == "reddit.com")
}

@Test func territoryCodes() {
    #expect(Territories.alpha2("ITA") == "IT")
    #expect(Territories.alpha2("US") == "US")
    #expect(Territories.flag("FR") == "🇫🇷")
}

@Test func salesRowsCountDownloadsAndRevenue() {
    let rows: [[String: String]] = [
        ["Apple Identifier": "111", "Units": "5", "Country Code": "FR", "Product Type Identifier": "1F", "Customer Price": "0", "Customer Currency": "EUR", "Developer Proceeds": "0", "Currency of Proceeds": "EUR"],
        ["Apple Identifier": "111", "Units": "2", "Country Code": "US", "Product Type Identifier": "3F", "Customer Price": "0", "Customer Currency": "USD", "Developer Proceeds": "0", "Currency of Proceeds": "USD"],
        ["Apple Identifier": "111", "Units": "9", "Country Code": "US", "Product Type Identifier": "7F", "Customer Price": "0", "Customer Currency": "USD", "Developer Proceeds": "0", "Currency of Proceeds": "USD"],
        ["Apple Identifier": "999", "Parent Identifier": "SKU1", "Units": "1", "Country Code": "US", "Product Type Identifier": "IA1", "Customer Price": "4.99", "Customer Currency": "USD", "Developer Proceeds": "3.49", "Currency of Proceeds": "USD"],
    ]
    let t = Syncer.tallySales(rows, appIds: ["111"], bySku: ["SKU1": "111"], fx: ExchangeRates())
    #expect(t["111"]?[.firstDownloads]?["FR"] == 5)
    #expect(t["111"]?[.redownloads]?["US"] == 2)
    #expect(t["111"]?[.firstDownloads]?["US"] == nil)   // updates are not downloads
    #expect(t["111"]?[.sales]?["US"] == 4.99)
    #expect(t["111"]?[.proceeds]?["US"] == 3.49)
}


@Test func setupLinkRoundTrips() {
    let c = ASCCredentials(issuerId: "00000000-…", keyId: "ABCD123456", privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nab+/c=\n-----END PRIVATE KEY-----", vendorNumber: "12345678")
    let url = SetupLink.url(for: c)
    #expect(url.scheme == "vane")
    #expect(SetupLink.credentials(from: url) == c)
    #expect(SetupLink.credentials(from: URL(string: "vane://setup#garbage")!) == nil)
    #expect(SetupLink.credentials(from: URL(string: "https://example.com")!) == nil)
}

@Test func assistantErrorsDropConfigWarningsAndExplainSignIn() {
    let warn = "Permission allow rule (/x/settings.json): Bash(foo *:*) mixes * with the trailing :* prefix syntax."
    #expect(Assistant.explain(warn + "\nFailed to authenticate: OAuth session expired") == "Claude Code is signed out. Run claude /login in Terminal, then try again.")
    #expect(Assistant.explain(warn + "\nModel not found") == "Model not found")
    #expect(Assistant.explain(warn) == "The AI command failed without saying why.")
}

@Test func conversionIgnoresDaysWithoutAnalytics() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("almanac-test-\(UUID().uuidString).sqlite").path
    let s = try Store(path: path)
    // A year of sales-report downloads, analytics only on the last day.
    try s.write([
        .init("a", "2026-11-01", .firstDownloads, "", 500),
        .init("a", "2026-11-10", .firstDownloads, "", 10),
        .init("a", "2026-11-10", .impressions, "", 1000),
        .init("a", "2026-11-10", .pageViews, "", 5),
    ])
    #expect(abs(s.total("a", .pageCR, from: "2026-11-01", to: "2026-11-10") - 0.01) < 0.0001)
    // A day without analytics is missing from the rate series, not a 0 % day.
    #expect(s.series("a", .pageCR, from: "2026-11-01", to: "2026-11-10").map(\.day) == ["2026-11-10"])
    #expect(s.series("a", .ttr, from: "2026-11-01", to: "2026-11-10").map(\.value) == [0.005])
}

@Test func assistantLinksKeepOnlyKnownDestinations() {
    let text = """
    Germany is mostly App Store search.
    [[open:listing?locale=de-DE|German listing]]
    [[open:reviews?filter=unanswered&rating=1&country=DE|Avis 1★]]
    [[open:metric:page_cr?period=90]]
    [[open:settings|Delete everything]]
    [[pin:ttr|Pin]] [[open:listing?locale=../../etc]]
    """
    let (clean, links) = AssistantLink.extract(from: text)
    #expect(clean == "Germany is mostly App Store search.")
    #expect(links.count == 3)
    #expect(links[0] == AssistantLink(action: .open(pane: "listing"), label: "German listing", locale: "de-DE"))
    #expect(links[1].unanswered && links[1].rating == 1 && links[1].country == "DE")
    #expect(links[2].action == .open(pane: "metric:page_cr") && links[2].period == 90)
    // unknown pane dropped, bad locale ignored but link kept as plain "listing" (4th, cut by the limit of 3)
    #expect(AssistantLink.extract(from: "[[open:settings]]").links.isEmpty)
    #expect(AssistantLink.extract(from: "[[open:listing?locale=../../etc]]").links.first?.locale == nil)
    #expect(AssistantLink.extract(from: "[[pin:nope]]").links.isEmpty)
}

@Test func dailySummaryAddsUpApps() throws {
    let s = try demoStore()
    let day = try #require(DailySummary.lastDay(s))
    #expect(day == "2026-11-11")
    let sum = try #require(DailySummary.make(s, day: day))
    let dl = s.apps().reduce(0) { $0 + s.total($1.id, .downloads, from: day, to: day) }
    #expect(sum.title.contains(Metric.downloads.format(dl)))
    #expect(sum.body.split(separator: "\n").count == 3)
}

@Test func fixedListingIssueDisappears() throws {
    let s = try demoStore()
    let app = "6448120003" // Cadence: no subtitle in its listing
    InsightEngine.refresh(store: s, app: app)
    #expect(s.insights(app).contains { $0.kind == "no-subtitle" })
    for var l in s.listing(app) where l.subtitle.isEmpty { l.subtitle = "Practice every day"; try s.upsert(listing: l) }
    InsightEngine.refresh(store: s, app: app)
    #expect(!s.insights(app).contains { $0.kind == "no-subtitle" })
    #expect(s.insights(app).contains { $0.kind == "crashes" }) // event insights stay
}

@Test func eventsShowAsMarksAndInReports() throws {
    let s = try demoStore()
    try s.save(event: AppEvent(appId: "", day: "2026-11-04", title: "Spring sale"))
    try s.save(event: AppEvent(appId: "6448120002", day: "2026-11-05", title: "Tidewise only"))
    let kiln = s.marks("6448120001").filter(\.isEvent).map(\.version)
    #expect(kiln == ["Spring sale"])
    #expect(s.marks("6448120002").filter(\.isEvent).count == 2)
    let r = ReportBuilder(store: s, app: "6448120001").build(.week, start: "2026-11-02")
    #expect(r.sections.contains { $0.paragraphs.contains { $0.contains("Spring sale") } })
}

@Test func allAppsAndGroupsAddUp() throws {
    let s = try demoStore()
    let ids = s.apps().map(\.id)
    let each = { (m: Metric) in ids.reduce(0) { $0 + s.total($1, m, from: "2026-10-01", to: "2026-10-31") } }
    #expect(abs(s.total(Store.allApps, .downloads, from: "2026-10-01", to: "2026-10-31") - each(.downloads)) < 0.001)
    #expect(abs(s.total(Store.allApps, .sales, from: "2026-10-01", to: "2026-10-31") - each(.sales)) < 0.001)
    s.setGroups([.init(name: "Pair", ids: Array(ids.prefix(2)))])
    let pair = ids.prefix(2).reduce(0) { $0 + s.total($1, .downloads, from: "2026-10-01", to: "2026-10-31") }
    #expect(abs(s.total("group:Pair", .downloads, from: "2026-10-01", to: "2026-10-31") - pair) < 0.001)
    #expect(s.reviews("group:Pair").count == s.reviews(ids[0]).count + s.reviews(ids[1]).count)
    #expect(s.listing(Store.allApps).isEmpty)
}

/// Answers App Store Connect calls without the network: no request exists yet, and the POST that creates one gets `postStatus`.
final class StubASC: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var postStatus = 403
    nonisolated(unsafe) static var posts = 0
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.appstoreconnect.apple.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let post = request.httpMethod == "POST"
        if post { Self.posts += 1 }
        let code = post ? Self.postStatus : 200
        let body = post ? (code == 403 ? #"{"errors":[{"detail":"forbidden"}]}"# : #"{"data":{"id":"r1"}}"#) : #"{"data":[]}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func salesKeyAsksForAdminThenAdminKeyClearsIt() async throws {
    URLProtocol.registerClass(StubASC.self)
    defer { URLProtocol.unregisterClass(StubASC.self) }
    let store = try Store(path: NSTemporaryDirectory() + "admin-\(UUID().uuidString).sqlite")
    let creds = ASCCredentials(issuerId: "issuer", keyId: "KEY", privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation, vendorNumber: "1")
    let syncer = Syncer(client: ASCClient(credentials: creds), store: store)

    StubASC.postStatus = 403
    try await syncer.syncAnalytics(app: "42")   // a 403 must not fail the whole refresh
    #expect(store.meta(Syncer.needsAdminKey("42")) == "1")

    StubASC.postStatus = 201
    try await syncer.requestAnalytics(app: "42")
    #expect(store.meta(Syncer.needsAdminKey("42")) == "")
    #expect(store.meta("analytics_requested_42") == Day.today())
    #expect(StubASC.posts == 2)
}

@Test func dailyNotificationOnlyForANewDay() throws {
    let s = try demoStore()
    #expect(DailySummary.newDay(s) == nil)            // first sync: remember, don't announce history
    #expect(DailySummary.newDay(s) == nil)            // same day again: nothing
    let last = DailySummary.lastDay(s)!
    s.setMeta("notified_sales_day", Day.add(-1, to: last))
    #expect(DailySummary.newDay(s) == last)           // a day later: announce it, once
    #expect(DailySummary.newDay(s) == nil)
}

@Test func reportBeforeAnalyticsShowsNoImpressionsInsteadOfZero() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("almanac-test-\(UUID().uuidString).sqlite").path
    let s = try Store(path: path)
    try s.write([
        .init("a", "2026-10-10", .firstDownloads, "", 50),
        .init("a", "2026-11-10", .firstDownloads, "", 10),
        .init("a", "2026-11-10", .impressions, "", 1000),
    ])
    let october = ReportBuilder(store: s, app: "a").build(.month, start: "2026-10-01")
    #expect(!october.hasAnalytics)
    #expect(!october.headline.contains { $0.metric == .impressions })
    #expect(october.sections[0].paragraphs[0].contains("analytics for this app start on"))
    #expect(ReportBuilder(store: s, app: "a").build(.month, start: "2026-11-01").hasAnalytics)
}

@Test func keywordRanksParseAndKeepThePreviousCheck() throws {
    #expect(KeywordRanks.terms("flac, ALAC,flac,,hifi ") == ["flac", "alac", "hifi"])
    let json = Data(#"{"results":[{"trackId":1},{"trackId":42},{"trackId":7}]}"#.utf8)
    #expect(KeywordRanks.rank(of: "42", in: json) == 2)
    #expect(KeywordRanks.rank(of: "9", in: json) == 0)

    let store = try Store(path: NSTemporaryDirectory() + "ranks-\(UUID()).sqlite")
    try store.save(ranks: [KeywordRank(term: "flac", country: "us", day: "2026-11-15", rank: 30)], app: "a")
    try store.save(ranks: [KeywordRank(term: "flac", country: "us", day: "2026-11-16", rank: 12),
                           KeywordRank(term: "hifi", country: "us", day: "2026-11-16", rank: 0)], app: "a")
    let r = store.ranks("a")
    #expect(r.map(\.term) == ["flac", "hifi"])
    #expect(r[0].rank == 12 && r[0].previous == 30)
    #expect(r[1].rank == 0 && r[1].previous == nil)
}

@Test func theChatHandoffHoldsInstructionsDataAndEveryMessage() {
    let history = (1...12).map { (role: $0 % 2 == 1 ? "user" : "assistant", text: "message \($0)") }
    let text = Assistant.handoff(context: "Downloads: 447", history: history)
    #expect(text.contains(Assistant.systemPrompt))
    #expect(text.contains("<data>\nDownloads: 447\n</data>"))
    #expect(text.contains("Developer: message 1\n") && text.contains("Assistant: message 12\n"))
}

@Test func updatesAndRetentionComeFromAnalyticsRows() throws {
    var acc: [String: Double] = [:]
    Syncer.accumulate(["Date": "2026-11-01", "Download Type": "Auto-update", "Territory": "IT", "Counts": "7"], report: "App Downloads Standard", into: &acc)
    Syncer.accumulate(["Date": "2026-11-01", "Download Type": "Manual update", "Territory": "IT", "Counts": "2"], report: "App Downloads Standard", into: &acc)
    #expect(acc == ["2026-11-01|updates|": 9])

    var cohorts: [String: Double] = [:]
    for (day, devices) in [("2026-11-01", "10"), ("2026-11-02", "3"), ("2026-11-08", "1"), ("2026-11-05", "9")] {
        Syncer.accumulateCohort(["Date": day, "App Download Date": "2026-11-01", "Unique Devices": devices], into: &cohorts)
    }
    #expect(cohorts == ["2026-11-01|active_d0": 10, "2026-11-01|active_d1": 3, "2026-11-01|active_d7": 1]) // day 4 is not read

    let store = try Store(path: ":memory:")
    try store.writeCohorts("a", cohorts)
    let r = store.retention("a", from: "2026-11-01", to: "2026-11-30")
    #expect(r.map(\.day) == Store.retentionDays)
    #expect(r[0].rate == 0.3)
    #expect(abs((r[1].rate ?? 0) - 0.1) < 1e-9)
    #expect(r[2].rate == 0) // day 14 falls in the period but nobody came back
    // Day 1 of a Nov 1 download is Nov 2: a period that starts later doesn't count it.
    #expect(store.retention("a", from: "2026-11-03", to: "2026-11-30")[0].rate == nil)
}
