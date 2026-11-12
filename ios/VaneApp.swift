import AlmanacCore
import SwiftUI

@main
struct VaneApp: App {
    @State private var model = AppModel()
    @State private var incoming: ASCCredentials?

    var body: some Scene {
        WindowGroup {
            @Bindable var model = model
            RootView()
                .environment(model)
                .sheet(isPresented: $model.settingsOpen) {
                    NavigationStack {
                        AccountSettings()
                            .navigationTitle("App Store Connect")
                            .toolbar { Button("Done") { model.settingsOpen = false } }
                    }
                    .environment(model)
                }
                .onOpenURL { incoming = SetupLink.credentials(from: $0) }
                .alert("Connect to App Store Connect?", isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } }),
                       presenting: incoming) { c in
                    Button("Connect") {
                        Keychain.save(c)
                        model.settingsOpen = false
                        Task { await model.refresh() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { c in Text("Use key \(c.keyId) from your Mac.") }
        }
    }
}
