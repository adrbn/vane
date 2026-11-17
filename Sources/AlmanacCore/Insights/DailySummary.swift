import Foundation

/// One day's downloads and proceeds across apps: the "new day arrived" notification.
public enum DailySummary {
    /// The newest day the sales reports cover, across apps.
    /// The sales day to announce, if a new one arrived since the last call. The first call only remembers the day:
    /// no notification for a year of imported history.
    public static func newDay(_ store: Store) -> String? {
        guard let day = lastDay(store) else { return nil }
        let previous = store.meta("notified_sales_day")
        store.setMeta("notified_sales_day", day)
        guard let previous, !previous.isEmpty, day > previous else { return nil }
        return day
    }

    public static func lastDay(_ store: Store) -> String? { store.apps().compactMap { store.lastDay($0.id, .firstDownloads) }.max() }

    /// Title and body for `day`, biggest apps first. Nil when nothing was downloaded or sold.
    public static func make(_ store: Store, day: String) -> (title: String, body: String)? {
        let rows = store.apps().map { a in (a.name, store.total(a.id, .downloads, from: day, to: day), store.total(a.id, .proceeds, from: day, to: day)) }
            .filter { $0.1 > 0 || $0.2 > 0 }.sorted { $0.1 > $1.1 }
        guard !rows.isEmpty else { return nil }
        let dl = rows.reduce(0) { $0 + $1.1 }, pr = rows.reduce(0) { $0 + $1.2 }
        let date = Day.date(day).formatted(.dateTime.weekday(.wide).day().month(.wide))
        let title = String(localized: "\(date): \(Metric.downloads.format(dl)) downloads, \(Metric.proceeds.format(pr))")
        let body = rows.count == 1 ? rows[0].0 : rows.prefix(3).map { "\($0.0) \(Metric.downloads.format($0.1)) · \(Metric.proceeds.format($0.2))" }.joined(separator: "\n")
        return (title, body)
    }

}
