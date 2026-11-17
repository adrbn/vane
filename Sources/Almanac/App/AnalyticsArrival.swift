import AlmanacCore
import Foundation
import UserNotifications

/// Apple's analytics show up one to two days after the key is added. Says so once, per app, when they land.
enum AnalyticsArrival {
    static func apps(_ store: Store) -> Set<String> {
        Set(store.apps().map(\.id).filter { !(store.meta("analytics_instances_\($0)") ?? "").isEmpty })
    }

    static func notify(_ store: Store, before: Set<String>) async {
        let now = apps(store)
        let names = store.apps().filter { now.contains($0.id) && !before.contains($0.id) }.map(\.name)
        guard !names.isEmpty, UserDefaults.standard.object(forKey: "notifyInsights") as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let c = UNMutableNotificationContent()
        c.title = String(localized: "Apple's analytics are here")
        c.body = String(localized: "Impressions, page views, conversion and sessions for \(names.formatted(.list(type: .and))).")
        c.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "analytics-\(names.joined())", content: c, trigger: nil))
    }
}

/// When a new day of sales lands: that day's downloads and proceeds, in the notification itself.
enum DailyNumbers {
    static func notify(_ store: Store) async {
        guard let day = DailySummary.newDay(store), let s = DailySummary.make(store, day: day),
              UserDefaults.standard.object(forKey: "notifyDaily") as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let c = UNMutableNotificationContent()
        c.title = s.title; c.body = s.body
        try? await center.add(UNNotificationRequest(identifier: "daily-\(day)", content: c, trigger: nil))
    }
}
