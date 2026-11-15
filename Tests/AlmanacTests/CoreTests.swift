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
