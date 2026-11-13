import AlmanacCore
import SwiftUI

struct AlmanacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Almanac") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.settingsOpen = true }.keyboardShortcut(",")
            }
            CommandGroup(after: .newItem) {
                Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r")
            }
            CommandGroup(after: .sidebar) {
                Button(model.chatOpen ? "Hide Chat" : "Show Chat") { model.chatOpen.toggle() }.keyboardShortcut("j")
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
