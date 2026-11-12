import SwiftUI

@main
struct VaneApp: App {
    @State private var model = AppModel()

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
        }
    }
}
