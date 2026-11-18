import AlmanacCore
import Foundation
import ServiceManagement
import UserNotifications

/// The same binary, launched by launchd with `--sync` every 6 hours
/// (Contents/Library/LaunchAgents/dev.almanac.agent.plist). Visible and switchable in
/// System Settings › General › Login Items.
enum BackgroundAgent {
    static let service = SMAppService.agent(plistName: "dev.almanac.agent.plist")

    static var isEnabled: Bool { service.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on { try service.register() } else { try service.unregister() }
    }

    /// Headless sync: fetch, detect, notify, exit.
    static func runHeadless() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            defer { done.signal() }
            let creds = Keychain.credentials()
            guard creds.isComplete, let store = try? Store(), store.meta("demo") != "1" else { return }
            let before = AnalyticsArrival.apps(store)
            let errors = await Syncer(client: ASCClient(credentials: creds), store: store).syncAll()
            // launchd keeps stderr in the unified log; also lets `Vane --sync` in Terminal show what failed.
            for e in errors { FileHandle.standardError.write(Data("\(e.step): \(e.message)\n".utf8)) }
            await AnalyticsArrival.notify(store, before: before)
            await DailyNumbers.notify(store)
            var fresh: [Insight] = []
            for app in store.apps() {
                fresh += InsightEngine.refresh(store: store, app: app.id)
            }
            let muted = InsightCategory.muted, mutedKinds = InsightCategory.mutedKinds
            await notify(fresh.filter { !muted.contains($0.category) && !mutedKinds.contains($0.kind) && ($0.needsAttention || $0.category == .milestones || $0.kind == "featured") })
        }
        done.wait()
    }

    static func notify(_ insights: [Insight]) async {
        guard UserDefaults.standard.object(forKey: "notifyInsights") as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        for i in insights.prefix(5) {
            let c = UNMutableNotificationContent()
            c.title = i.title
            c.body = i.body
            c.sound = .default
            try? await center.add(UNNotificationRequest(identifier: i.id, content: c, trigger: nil))
        }
    }
}
