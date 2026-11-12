import Foundation

/// Generates ~14 months of believable data for three fictional apps, so the whole UI
/// (and every insight rule) can be explored without an App Store Connect key.
public enum DemoData {
    struct RNG {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
        mutating func noise(_ amp: Double) -> Double { 1 + (next() * 2 - 1) * amp }
    }

    static let shares: [(String, Double)] = [
        ("US", 0.45), ("GB", 0.09), ("DE", 0.06), ("AU", 0.05), ("CA", 0.045), ("NZ", 0.028), ("FR", 0.026), ("NL", 0.02),
        ("MX", 0.019), ("JP", 0.016), ("BR", 0.014), ("SE", 0.012), ("IT", 0.012), ("IN", 0.012), ("DK", 0.011),
        ("CH", 0.01), ("ES", 0.01), ("AT", 0.009), ("NO", 0.008), ("BE", 0.008), ("IE", 0.007), ("KR", 0.007),
    ]

    struct Spec {
        var app: AppRecord
        var baseDownloads: Double, growth: Double, weekend: Double
        var price: Double, buyRate: Double, subsStart: Double, subsEnd: Double
        var featureDay: Int?            // days before the last day; nil = none
        var featureTerritory = "IT"
        var surgeTerritory: String?
        var ttrDropFromDay: Int?
        var crashSpike = false
        var ratingsDropVersionDay: Int?
        var versions: [(Int, String, String)]
    }

    public static func install(into store: Store, endingOn lastDay: String = Day.add(-1, to: Day.today())) throws {
        try store.removeAll()
        let specs = [
            Spec(app: AppRecord(id: "6448120001", name: "Kiln: Pottery Journal", bundleId: "app.kiln.journal", hue: 0.04),
                 baseDownloads: 360, growth: 0.55, weekend: 1.22, price: 4.99, buyRate: 0.13, subsStart: 290, subsEnd: 884,
                 featureDay: 5, versions: [(420, "1.0", "Launch"), (360, "1.1", "Glaze library"), (300, "1.2", "Firing schedules"),
                                           (210, "2.0", "Studio sync"), (120, "2.1", "Clay calculator"), (45, "2.2", "Widgets")]),
            Spec(app: AppRecord(id: "6448120002", name: "Tidewise", bundleId: "app.tidewise", hue: 0.55),
                 baseDownloads: 210, growth: 0.9, weekend: 1.35, price: 2.99, buyRate: 0.09, subsStart: 120, subsEnd: 610,
                 featureDay: nil, surgeTerritory: "ES",
                 versions: [(400, "3.0", "Redesign"), (250, "3.1", "Surf spots"), (90, "3.2", "Moon phases"), (20, "3.3", "Apple Watch")]),
            Spec(app: AppRecord(id: "6448120003", name: "Cadence: Practice Timer", bundleId: "app.cadence.practice", hue: 0.78),
                 baseDownloads: 140, growth: 0.25, weekend: 1.1, price: 1.99, buyRate: 0.11, subsStart: 210, subsEnd: 330,
                 featureDay: nil, ttrDropFromDay: 16, crashSpike: true, ratingsDropVersionDay: 30,
                 versions: [(380, "4.0", "Practice log"), (200, "4.1", "Drills"), (30, "4.2", "New tuner")]),
        ]
        let days = 430
        for (n, spec) in specs.enumerated() {
            var rng = RNG(state: UInt64(n + 1) * 7919)
            try store.upsert(app: spec.app)
            var samples: [Store.Sample] = []
            var ratingsTotal = 1200.0 * Double(n + 1)
            for back in stride(from: days - 1, through: 0, by: -1) {
                let day = Day.add(-back, to: lastDay)
                let t = Double(days - back) / 365
                let weekday = (Day.calendar.component(.weekday, from: Day.date(day)) + 5) % 7
                let wk = weekday >= 4 ? spec.weekend : 1
                var dl = spec.baseDownloads * (1 + spec.growth * t) * wk * rng.noise(0.12)
                if spec.surgeTerritory != nil && back == 0 { dl *= 1.9 } // fresh best day for Tidewise
                var browse = dl * 9 * rng.noise(0.1)
                var featureBoost = 0.0
                if let f = spec.featureDay, back <= f + 2, back >= 0 {
                    featureBoost = back <= f ? 22 * pow(0.78, Double(f - back)) : 0
                    browse *= 1 + featureBoost
                    dl *= 1 + featureBoost * 0.12
                }
                var ttr = 0.112 * rng.noise(0.05)
                if let d = spec.ttrDropFromDay, back <= d { ttr *= 0.66 }
                let cr = 0.224 * rng.noise(0.04)
                let views = dl / cr
                let impressions = views / ttr
                let first = dl * 0.75, re = dl * 0.25
                let priceNow = back < 210 ? spec.price : spec.price - 1
                let sales = dl * spec.buyRate * priceNow * (back < 210 ? 1.0 : 1.12) * rng.noise(0.15)
                let subs = spec.subsStart + (spec.subsEnd - spec.subsStart) * Double(days - back) / Double(days)
                var perK = 8.4
                if let v = spec.ratingsDropVersionDay, back <= v { perK = 2.9 }
                ratingsTotal += first * perK / 1000 * rng.noise(0.3)
                let sessions = (2400 + 1600 * t) * Double(n == 2 ? 1 : 2) * wk * rng.noise(0.08)
                var crashes = sessions * 0.0016 * rng.noise(0.3)
                if spec.crashSpike && back < 7 { crashes *= 3.2 }

                let a = spec.app.id
                samples += [
                    .init(a, day, .impressions, "", impressions), .init(a, day, .uniqueImpressions, "", impressions * 0.82),
                    .init(a, day, .pageViews, "", views), .init(a, day, .browseImpressions, "", browse),
                    .init(a, day, .searchImpressions, "", impressions * 0.68), .init(a, day, .firstDownloads, "", first),
                    .init(a, day, .redownloads, "", re), .init(a, day, .sales, "", sales), .init(a, day, .proceeds, "", sales * 0.7),
                    .init(a, day, .activeSubs, "", subs.rounded()), .init(a, day, .sessions, "", sessions),
                    .init(a, day, .crashes, "", crashes), .init(a, day, .ratingsTotal, "", ratingsTotal.rounded()),
                ]
                for (i, (code, share)) in shares.enumerated() {
                    var s = share * rng.noise(0.2)
                    let cv = 0.75 + Double((i * 37) % 11) / 20   // stable per-country conversion, 0.75–1.25×
                    if code == spec.featureTerritory && featureBoost > 0 { s *= 1 + featureBoost * 0.8 }
                    if code == spec.surgeTerritory && back < 7 { s *= 2.6 }
                    samples += [
                        .init(a, day, .impressions, code, impressions * s), .init(a, day, .pageViews, code, views * s),
                        .init(a, day, .firstDownloads, code, first * s * cv), .init(a, day, .redownloads, code, re * s * cv),
                        .init(a, day, .sales, code, sales * s * cv),
                    ]
                }
            }
            try store.write(samples)
            for (back, v, title) in spec.versions {
                try store.upsert(version: VersionMark(day: Day.add(-back, to: lastDay), version: v, title: title), app: spec.app.id)
            }
            for (i, r) in reviews(for: n, lastDay: lastDay).enumerated() {
                try store.upsert(review: Review(id: "\(spec.app.id)-r\(i)", appId: spec.app.id, rating: r.0, title: r.1, body: r.2,
                                                reviewer: r.3, territory: r.4, created: r.5, response: r.6))
            }
            for l in listings(spec.app.id, n) { try store.upsert(listing: l) }
        }
        store.setMeta("demo", "1")
        store.setMeta("last_sync", ISO8601DateFormatter().string(from: Date()))
    }

    static func listings(_ app: String, _ n: Int) -> [ListingLocale] {
        switch n {
        case 0: return [
            ListingLocale(appId: app, locale: "en-US", name: "Kiln: Pottery Journal", subtitle: "Glaze notes and firing logs",
                          keywords: "pottery,ceramics,clay,glaze,wheel,studio,stoneware,porcelain,cone,bisque,raku,throwing",
                          promoText: "New: home screen widgets for your next firing.", description: "Kiln keeps every pot, glaze and firing in one place."),
            ListingLocale(appId: app, locale: "fr-FR", name: "Kiln : Journal de poterie", subtitle: "Émaux et cuissons",
                          keywords: "poterie,céramique,argile,tour,atelier,grès,porcelaine,biscuit,raku,émaillage,four",
                          promoText: "", description: "Kiln garde chaque pièce, émail et cuisson au même endroit."),
        ]
        case 1: return [
            ListingLocale(appId: app, locale: "en-US", name: "Tidewise", subtitle: "Tide tables for surf and sail",
                          keywords: "tide,surf,sailing,fishing,moon,coast", promoText: "", description: "Accurate tides for 8,000 stations."),
        ]
        default: return [
            ListingLocale(appId: app, locale: "en-US", name: "Cadence: Practice Timer", subtitle: "",
                          keywords: "metronome,practice,music,piano,guitar,violin,drums,tempo,rhythm,tuner,scales,habit",
                          promoText: "", description: "Practice with intent."),
        ]
        }
    }

    // rating, title, body, reviewer, territory(alpha-3), day, response
    static func reviews(for n: Int, lastDay: String) -> [(Int, String, String, String, String, String, String?)] {
        let own: [(String, String, String, String)] = [
            [("Finally organised", "I used to keep glaze notes on scraps of paper. This replaced all of it.", "mudhands", "USA"),
             ("Bellissima", "La uso per ogni cottura, chiara e veloce. Grazie!", "ceramica_roma", "ITA")],
            [("Spot on", "Tide times match the harbour board to the minute.", "saltyskipper", "GBR"),
             ("Muy útil", "La uso cada mañana antes de salir a pescar.", "pescador_cadiz", "ESP")],
            [("Finally practising daily", "The streaks keep me honest. Scales every morning now.", "cellolea", "USA"),
             ("Bellissima", "La uso per studiare il pianoforte ogni giorno. Grazie!", "pianista_roma", "ITA")],
        ][n]
        let good = own + [
            ("Exactly what I needed", "Simple, fast, and the widgets are lovely.", "kpw", "GBR"),
            ("Super App", "Endlich alles an einem Ort. Sehr gut gemacht.", "lena_b", "DEU"),
            ("Très pratique", "Simple et efficace, je recommande.", "camille.l", "FRA"),
            ("Love it", "Worth every cent. The developer actually listens.", "j.ortega", "MEX"),
            ("Great", "Does one thing very well.", "sam_k", "AUS"),
        ]
        let bad: [(String, String, String, String)] = n == 2 ? [
            ("Crashes on launch", "Since the last update it crashes every time I open the tuner.", "violin_dad", "USA"),
            ("Broken after update", "The new tuner doesn't work on my iPad. Please fix.", "mkr", "CAN"),
            ("Lost my log", "Practice history disappeared after updating. Very frustrating.", "grace.h", "GBR"),
            ("Too many prompts", "Stop asking me to subscribe every session.", "noel", "USA"),
        ] : [
            ("Too many prompts", "Stop asking me to subscribe every time I open it.", "noel", "USA"),
            ("Sync is slow", "Takes ages to show up on my iPad.", "mkr", "CAN"),
        ]
        var out: [(Int, String, String, String, String, String, String?)] = []
        var rng = RNG(state: UInt64(n + 11) * 104729)
        for i in 0..<28 {
            let day = Day.add(-(i * 3 + Int(rng.next() * 3)), to: lastDay)
            let isBad = n == 2 ? i < 8 && i % 4 != 3 : rng.next() < 0.12
            if isBad {
                let b = bad[i % bad.count]
                out.append((1 + Int(rng.next() * 2), b.0, b.1, b.2, b.3, day, nil))
            } else {
                let g = good[i % good.count]
                out.append((rng.next() < 0.8 ? 5 : 4, g.0, g.1, g.2, g.3, day, i % 5 == 4 ? "Thank you, this made my day!" : nil))
            }
        }
        return out
    }
}
