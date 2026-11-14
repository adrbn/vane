import AlmanacCore
import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

enum Pane: Hashable {
    case insights, listing, reviews, appStore, sales, usage, territories
    case metric(Metric)

    /// `--pane sales` or `--pane metric:downloads` opens straight on that screen (used for screenshots).
    static var fromLaunchArgument: Pane? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--pane"), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        if v.hasPrefix("metric:") { return Metric(rawValue: String(v.dropFirst(7))).map(Pane.metric) }
        return ["insights": .insights, "listing": .listing, "reviews": .reviews, "appStore": .appStore,
                "sales": .sales, "usage": .usage, "territories": .territories][v]
    }
}

struct ReportRef: Codable, Hashable {
    var appId: String
    var period: ReportPeriod
    var start: String
}

@Observable @MainActor
final class AppModel {
    let store: Store
    var apps: [AppRecord] = []
    var appId: String? { didSet { UserDefaults.standard.set(appId, forKey: "selectedApp") } }
    var selection: Pane? = Pane.fromLaunchArgument ?? .appStore { // bound straight to the sidebar List
        didSet {
            guard !navigating, let old = oldValue, old != selection else { return }
            backStack.append(old); forwardStack = []
        }
    }
    var section: Pane {
        get { selection ?? .appStore }
        set { selection = newValue }
    }
    // Insights the user hasn't looked at yet: a red dot on Insights in the sidebar until the screen is opened.
    var seenInsights = Set(UserDefaults.standard.stringArray(forKey: "insights.seen") ?? [])
    var hasUnseenInsights: Bool { insights().contains { !seenInsights.contains($0.id) } }
    func markInsightsSeen() {
        let ids = Set(insights().map(\.id))
        guard !ids.isSubset(of: seenInsights) else { return }
        seenInsights.formUnion(ids)
        UserDefaults.standard.set(Array(seenInsights), forKey: "insights.seen")
    }
    /// Categories the user turned off: hidden everywhere and never notified.
    var mutedCategories = InsightCategory.muted {
        didSet { UserDefaults.standard.set(mutedCategories.map(\.rawValue).sorted(), forKey: InsightCategory.mutedKey) }
    }
    /// The selected app's insights without the muted categories.
    func insights(includeDismissed: Bool = false) -> [Insight] {
        store.insights(appId ?? "", includeDismissed: includeDismissed).filter { !mutedCategories.contains($0.category) }
    }
    // Back/forward through visited screens, like Safari: ⌘[ ⌘] or a two-finger swipe.
    private var backStack: [Pane] = []
    private var forwardStack: [Pane] = []
    @ObservationIgnored private var navigating = false
    // -1…1 while a swipe is tracked; drives the edge arrow. `--swipe-preview 0.5` freezes it for screenshots.
    var swipeProgress: CGFloat = CommandLine.arguments.firstIndex(of: "--swipe-preview").flatMap { i in
        i + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[i + 1]).map { CGFloat($0) } : nil } ?? 0
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    func goBack() { step(from: &backStack, to: &forwardStack) }
    func goForward() { step(from: &forwardStack, to: &backStack) }
    private func step(from: inout [Pane], to: inout [Pane]) {
        guard let p = from.popLast() else { return }
        to.append(section)
        navigating = true; selection = p; navigating = false
    }
    var chatOpen = CommandLine.arguments.contains("--chat")
    var settingsOpen = CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--about")   // Mac: in-window sheet; iOS: modal sheet
    var settingsAbout = CommandLine.arguments.contains("--about")   // Mac: open Settings on the About tab
    /// First launch without a key (never in `--demo`); `--onboarding` forces it for screenshots.
    var onboardingOpen = CommandLine.arguments.contains("--onboarding")
        || (!CommandLine.arguments.contains("--demo") && !Keychain.credentials().isComplete && !UserDefaults.standard.bool(forKey: "onboarded"))
    var chatContext = ""
    var chatSeed: String?               // question pre-filled by "Ask about this" buttons
    var syncing = false
    var syncStatus = ""
    var syncErrors: [String] = []
    var revision = 0                    // bump → views re-read the store
    var pinned: [Metric] {
        didSet { UserDefaults.standard.set(pinned.map(\.rawValue), forKey: "pinned") }
    }

    var app: AppRecord? { apps.first { $0.id == appId } }
    var isDemo: Bool { demoLaunch || store.meta("demo") == "1" }
    /// The `--demo` window: never syncs, so real data can't land in its database.
    let demoLaunch = CommandLine.arguments.contains("--demo")
    var lastSync: Date? { store.meta("last_sync").flatMap { ISO8601DateFormatter().date(from: $0) } }

    init() {
        // `--demo` opens a throwaway database with the demo apps (screenshots), never touching the real one.
        let demo = CommandLine.arguments.contains("--demo")
        let path = demo ? NSTemporaryDirectory() + "almanac-demo.sqlite" : Store.defaultPath
        do { store = try Store(path: path) } catch { fatalError("Can't open the database: \(error)") }
        // Before reload(): it falls back to the first app, and that would overwrite the saved choice.
        appId = UserDefaults.standard.string(forKey: "selectedApp")
        pinned = (UserDefaults.standard.stringArray(forKey: "pinned") ?? ["unique_impressions", "ttr", "downloads", "first_downloads", "active_subs"])
            .compactMap(Metric.init(rawValue:))
        // A demo database that a sync once filled with real apps (before demoLaunch existed) is reset.
        if demo && store.meta("demo") != "1" { try? store.removeAll() }
        reload()
        if apps.isEmpty && (demo || !Keychain.credentials().isComplete) { loadDemo() }
        // Re-run the engine on launch so stored insights pick up the current format (charts, wording) before the next sync.
        else { runEngine() }
        if appId == nil || !apps.contains(where: { $0.id == appId }) { appId = apps.first?.id }
    }

    func reload() {
        apps = store.apps()
        if appId == nil || !apps.contains(where: { $0.id == appId }) { appId = apps.first?.id }
        revision += 1
    }

    func loadDemo() {
        try? DemoData.install(into: store)
        runEngine()
        reload()
    }

    @discardableResult
    func runEngine() -> [Insight] {
        apps = store.apps()
        return apps.flatMap { (try? store.merge(insights: InsightEngine(store: store, app: $0.id).run())) ?? [] }
    }

    func refresh() async {
        let creds = Keychain.credentials()
        guard creds.isComplete, !demoLaunch else {
            if isDemo { loadDemo() }
            return
        }
        guard !syncing else { return }
        if isDemo { try? store.removeAll() }
        syncing = true; syncErrors = []
        #if os(iOS)
        // A few more minutes if the user leaves the app mid-sync.
        let bg = UIApplication.shared.beginBackgroundTask(withName: "sync")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        #endif
        let before = AnalyticsArrival.apps(store)
        let syncer = Syncer(client: ASCClient(credentials: creds), store: store)
        let errors = await syncer.syncAll { step in Task { @MainActor in self.syncStatus = step; self.reload() } }
        syncErrors = errors.map { "\($0.step): \($0.message)" }
        await AnalyticsArrival.notify(store, before: before)
        runEngine()
        reload()
        syncing = false; syncStatus = ""
    }

    func dismiss(_ insight: Insight) {
        try? store.dismiss(insight: insight.id)
        revision += 1
    }

    func togglePin(_ m: Metric) {
        if let i = pinned.firstIndex(of: m) { pinned.remove(at: i) } else { pinned.append(m) }
    }

    func ask(_ question: String) {
        chatSeed = question
        chatOpen = true
    }

    var syncer: Syncer? {
        let c = Keychain.credentials()
        return c.isComplete && !isDemo ? Syncer(client: ASCClient(credentials: c), store: store) : nil
    }
}

extension InsightCategory {
    static let mutedKey = "insights.muted"
    static var muted: Set<InsightCategory> {
        Set((UserDefaults.standard.stringArray(forKey: mutedKey) ?? []).compactMap(InsightCategory.init(rawValue:)))
    }
}
