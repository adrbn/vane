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
        return Pane(name: args[i + 1])
    }

    /// `sales`, `metric:downloads`… shared by launch flags and the assistant's buttons.
    init?(name v: String) {
        if v.hasPrefix("metric:") {
            guard let m = Metric(rawValue: String(v.dropFirst(7))) else { return nil }
            self = .metric(m); return
        }
        guard let p = (["insights": .insights, "listing": .listing, "reviews": .reviews, "appStore": .appStore,
                        "sales": .sales, "usage": .usage, "territories": .territories] as [String: Pane])[v] else { return nil }
        self = p
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
    /// Single kinds the user turned off from an insight's menu ("Stop Showing…").
    var mutedKinds = InsightCategory.mutedKinds {
        didSet { UserDefaults.standard.set(mutedKinds.sorted(), forKey: InsightCategory.mutedKindsKey) }
    }
    /// The selected app's insights without the muted categories and kinds.
    func insights(includeDismissed: Bool = false) -> [Insight] {
        store.insights(appId ?? "", includeDismissed: includeDismissed).filter { !mutedCategories.contains($0.category) && !mutedKinds.contains($0.kind) }
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
    var eventsOpen = CommandLine.arguments.contains("--events")
    var chatContext = ""
    var chatSeed: String?               // question pre-filled by "Ask about this" buttons
    var pendingLink: AssistantLink?     // filters for the screen an assistant button opened; that screen applies and clears it
    var syncing = false
    var syncStatus = ""
    var syncErrors: [String] = []
    var revision = 0                    // bump → views re-read the store
    var pinned: [Metric] {
        didSet { UserDefaults.standard.set(pinned.map(\.rawValue), forKey: "pinned") }
    }

    /// The selected app, or a stand-in record for "All apps" and groups (their numbers are summed by the store).
    var app: AppRecord? {
        guard let appId else { return nil }
        if isAggregate { return store.displayName(appId).map { AppRecord(id: appId, name: $0, bundleId: "", hue: 0.6) } }
        return apps.first { $0.id == appId }
    }
    var isAggregate: Bool { appId.map(Store.isAggregate) ?? false }
    var groups: [Store.AppGroup] { _ = revision; return store.groups() }
    var groupsOpen = false
    private func isValid(_ id: String?) -> Bool {
        guard let id, !store.appIds(id).isEmpty else { return false }
        return Store.isAggregate(id) || apps.contains { $0.id == id }
    }
    /// Apps whose analytics reports wait on the one-time Admin request (the key is Sales and Reports).
    var appsNeedingAdmin: [AppRecord] { _ = revision; return apps.filter { store.meta(Syncer.needsAdminKey($0.id)) == "1" } }
    var needsAdmin: Bool { appsNeedingAdmin.contains { $0.id == appId } }
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
        // `--demo --needs-admin`: the first demo app has sales only and waits on the Admin step (screenshots).
        if demo && CommandLine.arguments.contains("--needs-admin"), let first = store.apps().first?.id {
            try? store.db.query("DELETE FROM daily WHERE app_id=? AND metric NOT IN ('sales','proceeds','first_downloads','redownloads')", [first])
            store.setMeta(Syncer.needsAdminKey(first), "1")
        }
        // Re-run the engine on launch so stored insights pick up the current format (charts, wording) before the next sync.
        else { runEngine() }
        if !isValid(appId) { appId = apps.first?.id }
    }

    func reload() {
        apps = store.apps()
        if !isValid(appId) { appId = apps.first?.id }
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
        return apps.flatMap { InsightEngine.refresh(store: store, app: $0.id) }
    }

    /// On launch and when the window comes back: a refresh if the last one is over 15 minutes old.
    func refreshIfStale() async {
        guard (lastSync.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true) else { return }
        await refresh()
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
        await DailyNumbers.notify(store)
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

    /// An assistant button: navigate (and set the period or the screen's filters) or pin a chart. Nothing else.
    func follow(_ link: AssistantLink) {
        switch link.action {
        case .pin(let m): if !pinned.contains(m) { pinned.append(m) }
        case .open(let name):
            guard let pane = Pane(name: name) else { return }
            if let days = link.period { UserDefaults.standard.set(days, forKey: "period") }
            pendingLink = name == "listing" || name == "reviews" ? link : nil   // the only screens with filters to apply
            selection = pane
        }
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
    static let mutedKindsKey = "insights.mutedKinds"
    static var mutedKinds: Set<String> { Set(UserDefaults.standard.stringArray(forKey: mutedKindsKey) ?? []) }
    static var muted: Set<InsightCategory> {
        Set((UserDefaults.standard.stringArray(forKey: mutedKey) ?? []).compactMap(InsightCategory.init(rawValue:)))
    }
}
