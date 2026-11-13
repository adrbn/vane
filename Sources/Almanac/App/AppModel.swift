import AlmanacCore
import Foundation
import Observation

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
    var selection: Pane? = Pane.fromLaunchArgument ?? .insights   // bound straight to the sidebar List
    var section: Pane {
        get { selection ?? .insights }
        set { selection = newValue }
    }
    var chatOpen = CommandLine.arguments.contains("--chat")
    var settingsOpen = CommandLine.arguments.contains("--settings")   // Mac: in-window sheet; iOS: modal sheet
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
    var isDemo: Bool { store.meta("demo") == "1" }
    var lastSync: Date? { store.meta("last_sync").flatMap { ISO8601DateFormatter().date(from: $0) } }

    init() {
        // `--demo` opens a throwaway database with the demo apps (screenshots), never touching the real one.
        let demo = CommandLine.arguments.contains("--demo")
        let path = demo ? NSTemporaryDirectory() + "almanac-demo.sqlite" : Store.defaultPath
        do { store = try Store(path: path) } catch { fatalError("Can't open the database: \(error)") }
        pinned = (UserDefaults.standard.stringArray(forKey: "pinned") ?? ["unique_impressions", "ttr", "downloads", "first_downloads", "active_subs"])
            .compactMap(Metric.init(rawValue:))
        reload()
        if apps.isEmpty && (demo || !Keychain.credentials().isComplete) { loadDemo() }
        appId = UserDefaults.standard.string(forKey: "selectedApp").flatMap { id in apps.contains { $0.id == id } ? id : nil } ?? apps.first?.id
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
        guard creds.isComplete else {
            if isDemo { loadDemo() }
            return
        }
        if isDemo { try? store.removeAll() }
        syncing = true; syncErrors = []
        let syncer = Syncer(client: ASCClient(credentials: creds), store: store)
        let errors = await syncer.syncAll { step in Task { @MainActor in self.syncStatus = step } }
        syncErrors = errors.map { "\($0.step): \($0.message)" }
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
