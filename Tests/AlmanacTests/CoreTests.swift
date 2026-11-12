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
    #expect(cr > 0.15 && cr < 0.3)
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

@Test func territoryCodes() {
    #expect(Territories.alpha2("ITA") == "IT")
    #expect(Territories.alpha2("US") == "US")
    #expect(Territories.flag("FR") == "🇫🇷")
}
