import AlmanacCore
import SwiftUI

struct AlmanacApp: App {
    @State private var model = AppModel()
    init() { _ = Updater.controller }   // start the scheduled checks at launch, not on first menu open

    var body: some Scene {
        WindowGroup("Vane") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Vane") { model.settingsAbout = true; model.settingsOpen = true }
                Updater.menuItem
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.settingsOpen = true }.keyboardShortcut(",")
            }
            CommandGroup(after: .newItem) {
                Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r")
                Button("Events…") { model.eventsOpen = true }.keyboardShortcut("e")
            }
            CommandGroup(after: .sidebar) {
                Button(model.chatOpen ? "Hide Chat" : "Show Chat") { model.chatOpen.toggle() }.keyboardShortcut("j")
                Divider()
                Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(!model.canGoBack)
                Button("Forward") { model.goForward() }.keyboardShortcut("]").disabled(!model.canGoForward)
            }
        }

        WindowGroup("Report", id: "report", for: ReportRef.self) { $ref in
            if let ref {
                ReportView(ref: ref).environment(model).frame(minWidth: 960, minHeight: 600)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
    }
}
