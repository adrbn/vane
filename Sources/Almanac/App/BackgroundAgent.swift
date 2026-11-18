import AlmanacCore
import Foundation
import ServiceManagement

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
            await InsightNotifier.post(fresh)
        }
        done.wait()
    }
}
