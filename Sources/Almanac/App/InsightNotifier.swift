import AlmanacCore
import Foundation
import UserNotifications

/// New insights worth a notification, shared by the Mac's background agent and the iPhone's background refresh.
enum InsightNotifier {
    static func post(_ fresh: [Insight]) async {
        guard UserDefaults.standard.object(forKey: "notifyInsights") as? Bool ?? true else { return }
        let muted = InsightCategory.muted, mutedKinds = InsightCategory.mutedKinds
        let worth = fresh.filter { !muted.contains($0.category) && !mutedKinds.contains($0.kind) && ($0.needsAttention || $0.category == .milestones || $0.kind == "featured") }
        guard !worth.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        for i in worth.prefix(5) {
            let c = UNMutableNotificationContent()
            c.title = i.title
            c.body = i.body
            c.sound = .default
            try? await center.add(UNNotificationRequest(identifier: i.id, content: c, trigger: nil))
        }
    }
}
