import Foundation

/// Calendar day stored as "yyyy-MM-dd" (UTC). Strings sort chronologically.
public enum Day {
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func string(_ date: Date) -> String { formatter.string(from: date) }
    /// Noon UTC, so the day displays correctly in every user time zone.
    public static func date(_ day: String) -> Date { formatter.date(from: day)?.addingTimeInterval(12 * 3600) ?? .distantPast }
    public static func today() -> String { string(Date()) }

    public static func add(_ days: Int, to day: String) -> String {
        string(calendar.date(byAdding: .day, value: days, to: date(day))!)
    }

    public static func between(_ a: String, _ b: String) -> Int {
        calendar.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }

    /// Monday of the week containing `day`.
    public static func weekStart(_ day: String) -> String {
        let d = date(day)
        let wd = calendar.component(.weekday, from: d) // 1 = Sunday
        return add(-((wd + 5) % 7), to: day)
    }

    public static func monthStart(_ day: String) -> String { String(day.prefix(7)) + "-01" }
    public static func yearStart(_ day: String) -> String { String(day.prefix(4)) + "-01-01" }
}

public enum Granularity: String, CaseIterable, Identifiable, Sendable {
    case day = "Day", week = "Week", month = "Month", year = "Year"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        case .year: String(localized: "Year")
        }
    }

    public func bucket(_ day: String) -> String {
        switch self {
        case .day: return day
        case .week: return Day.weekStart(day)
        case .month: return Day.monthStart(day)
        case .year: return Day.yearStart(day)
        }
    }
}

public struct Point: Hashable, Sendable, Identifiable {
    public var day: String
    public var value: Double
    public var id: String { day }
    public var date: Date { Day.date(day) }
    public init(day: String, value: Double) { self.day = day; self.value = value }
}

public extension Array where Element == Point {
    var total: Double { reduce(0) { $0 + $1.value } }
    var average: Double { isEmpty ? 0 : total / Double(count) }

    /// Sums (or averages, for gauges) values into buckets.
    func bucketed(_ g: Granularity, average: Bool = false) -> [Point] {
        var sums: [String: (Double, Int)] = [:]
        for p in self {
            let k = g.bucket(p.day)
            let s = sums[k] ?? (0, 0)
            sums[k] = (s.0 + p.value, s.1 + 1)
        }
        return sums.keys.sorted().map { k in
            let s = sums[k]!
            return Point(day: k, value: average ? s.0 / Double(s.1) : s.0)
        }
    }
}
