import Foundation

public struct AppRecord: Identifiable, Hashable, Sendable {
    public var id: String          // App Store Apple ID
    public var name: String
    public var bundleId: String
    public var hue: Double         // 0…1, used for the generated icon
    public init(id: String, name: String, bundleId: String, hue: Double) {
        self.id = id; self.name = name; self.bundleId = bundleId; self.hue = hue
    }
}

/// Every daily series Almanac stores. Raw values are the column names in `daily`.
public enum Metric: String, CaseIterable, Identifiable, Sendable {
    case impressions, uniqueImpressions = "unique_impressions", pageViews = "page_views"
    case browseImpressions = "browse_impressions", searchImpressions = "search_impressions"
    case firstDownloads = "first_downloads", redownloads
    case sales, proceeds, activeSubs = "active_subs"
    case sessions, crashes, ratingsTotal = "ratings_total"
    // Derived (computed from the above, never stored)
    case downloads, ttr, pageCR = "page_cr", newRatings = "new_ratings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .impressions: "Impressions"
        case .uniqueImpressions: "Unique impressions"
        case .pageViews: "Product page views"
        case .browseImpressions: "Browse impressions"
        case .searchImpressions: "Search impressions"
        case .firstDownloads: "First-time downloads"
        case .redownloads: "Redownloads"
        case .downloads: "Total downloads"
        case .sales: "Sales"
        case .proceeds: "Proceeds"
        case .activeSubs: "Active subscriptions"
        case .sessions: "Sessions"
        case .crashes: "Crashes"
        case .ratingsTotal: "Total ratings"
        case .newRatings: "New ratings"
        case .ttr: "Tap-through rate"
        case .pageCR: "Page conversion rate"
        }
    }

    public var isCurrency: Bool { self == .sales || self == .proceeds }
    public var isRate: Bool { self == .ttr || self == .pageCR }
    /// Gauges are snapshots: aggregate by average/last, not by sum.
    public var isGauge: Bool { self == .activeSubs || self == .ratingsTotal || isRate }
    /// Metrics that have a per-territory breakdown.
    public var hasTerritories: Bool {
        [.impressions, .pageViews, .firstDownloads, .redownloads, .downloads, .sales].contains(self)
    }

    public func format(_ v: Double) -> String {
        if isRate { return String(format: "%.2f%%", v * 100) }
        if isCurrency { return v.formatted(.currency(code: "USD")) }
        return Int(v.rounded()).formatted()
    }
}

public struct VersionMark: Identifiable, Hashable, Sendable {
    public var day: String
    public var version: String
    public var title: String
    public var id: String { day + version }
    public init(day: String, version: String, title: String) { self.day = day; self.version = version; self.title = title }
}

public struct Review: Identifiable, Hashable, Sendable {
    public var id: String
    public var appId: String
    public var rating: Int
    public var title: String
    public var body: String
    public var reviewer: String
    public var territory: String
    public var created: String
    public var response: String?
    public init(id: String, appId: String, rating: Int, title: String, body: String, reviewer: String, territory: String, created: String, response: String?) {
        self.id = id; self.appId = appId; self.rating = rating; self.title = title; self.body = body
        self.reviewer = reviewer; self.territory = territory; self.created = created; self.response = response
    }
}

public struct ListingLocale: Identifiable, Hashable, Sendable {
    public var appId: String
    public var locale: String
    public var name: String
    public var subtitle: String
    public var keywords: String
    public var promoText: String
    public var description: String
    public var versionLocalizationId: String?   // for PATCH keywords/description/promo
    public var infoLocalizationId: String?      // for PATCH name/subtitle
    public var id: String { appId + locale }
    public init(appId: String, locale: String, name: String, subtitle: String, keywords: String, promoText: String, description: String, versionLocalizationId: String? = nil, infoLocalizationId: String? = nil) {
        self.appId = appId; self.locale = locale; self.name = name; self.subtitle = subtitle; self.keywords = keywords
        self.promoText = promoText; self.description = description
        self.versionLocalizationId = versionLocalizationId; self.infoLocalizationId = infoLocalizationId
    }
}

public enum InsightCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case discovery, conversion, revenue, ratings, markets, retention, milestones, reports
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .discovery: "magnifyingglass"
        case .conversion: "arrow.down.circle"
        case .revenue: "dollarsign.circle"
        case .ratings: "star"
        case .markets: "globe"
        case .retention: "arrow.triangle.2.circlepath"
        case .milestones: "flag.checkered"
        case .reports: "doc.text"
        }
    }
}

public enum InsightAction: Codable, Hashable, Sendable {
    case fixKeywords(locale: String, keywords: String)
    case openReport(period: String, start: String)
    case openMetric(String)
}

public struct Insight: Identifiable, Hashable, Sendable, Codable {
    public var id: String            // stable: app|kind|key, so re-running the engine doesn't duplicate
    public var appId: String
    public var kind: String
    public var category: InsightCategory
    public var title: String
    public var body: String
    public var day: String
    public var needsAttention: Bool
    public var chart: InsightChart?
    public var action: InsightAction?
    public var dismissed = false

    public init(id: String, appId: String, kind: String, category: InsightCategory, title: String, body: String, day: String, needsAttention: Bool = false, chart: InsightChart? = nil, action: InsightAction? = nil) {
        self.id = id; self.appId = appId; self.kind = kind; self.category = category; self.title = title
        self.body = body; self.day = day; self.needsAttention = needsAttention; self.chart = chart; self.action = action
    }
}

public struct InsightChart: Codable, Hashable, Sendable {
    public var label: String
    public var points: [ChartPoint]
    public var baselineLabel: String?
    public var baseline: Double?
    public var headline: String
    public var isBigNumber = false
    public init(label: String, points: [ChartPoint], baselineLabel: String? = nil, baseline: Double? = nil, headline: String, isBigNumber: Bool = false) {
        self.label = label; self.points = points; self.baselineLabel = baselineLabel; self.baseline = baseline
        self.headline = headline; self.isBigNumber = isBigNumber
    }
}

public struct ChartPoint: Codable, Hashable, Sendable, Identifiable {
    public var day: String
    public var value: Double
    public var id: String { day }
    public var date: Date { Day.date(day) }
    public init(_ p: Point) { day = p.day; value = p.value }
}
