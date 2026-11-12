import AlmanacCore
import SwiftUI

struct AlmanacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Almanac") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r")
            }
            CommandGroup(after: .sidebar) {
                Button(model.chatOpen ? "Hide Chat" : "Show Chat") { model.chatOpen.toggle() }.keyboardShortcut("j")
            }
        }

        WindowGroup("Report", id: "report", for: ReportRef.self) { $ref in
            if let ref {
                ReportView(ref: ref).environment(model).frame(minWidth: 760, minHeight: 600)
            }
        }
        .defaultSize(width: 980, height: 860)

        Settings {
            SettingsView().environment(model).frame(width: 540)
        }
    }
}
