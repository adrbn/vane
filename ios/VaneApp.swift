import AlmanacCore
import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct VaneApp: App {
    @State private var model = AppModel()
    @State private var incoming: ASCCredentials?

    var body: some Scene {
        WindowGroup {
            PhoneRoot()
                .environment(model)
                .onOpenURL { incoming = SetupLink.credentials(from: $0) }
                .alert("Connect to App Store Connect?", isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } }),
                       presenting: incoming) { c in
                    Button("Connect") {
                        Keychain.save(c)
                        UserDefaults.standard.set(true, forKey: "onboarded")
                        model.onboardingOpen = false
                        Task { await model.refresh() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { c in Text("Use key \(c.keyId) from your Mac.") }
                .task {
                    // Asked once, so the background refresh can say when something needs attention.
                    if Keychain.credentials().isComplete { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                }
        }
        .onChange(of: phase) { _, p in if p == .background { Self.schedule() } }
        // iOS decides when this runs (often a few times a day, less on a phone that's rarely opened).
        .backgroundTask(.appRefresh(Self.refreshTask)) {
            Self.schedule()
            await model.refresh()
        }
    }

    @Environment(\.scenePhase) private var phase
    static let refreshTask = "com.adrbn.vane.refresh"

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: refreshTask)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }
}
