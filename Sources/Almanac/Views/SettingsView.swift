import AlmanacCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettings().tabItem { Label("App Store Connect", systemImage: "key") }
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
        }
        .padding(20)
        .frame(width: 560, height: 620)
    }
}

struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @State private var creds = Keychain.credentials()
    @State private var status: String?
    @State private var testing = false
    @State private var importing = false
    @State private var agentOn = BackgroundAgent.isEnabled

    var body: some View {
        Form {
            Section {
                TextField("Issuer ID", text: $creds.issuerId)
                TextField("Key ID", text: $creds.keyId)
                LabeledContent("Private key") {
                    HStack {
                        Text(creds.privateKeyPEM.isEmpty ? "None" : "AuthKey loaded").foregroundStyle(.secondary)
                        Button("Choose .p8…") { importing = true }
                    }
                }
                TextField("Vendor number", text: $creds.vendorNumber, prompt: Text("For sales reports, e.g. 87654321"))
            } footer: {
                Text("Create a key in App Store Connect › Users and Access › Integrations. The Sales and Reports role is enough for analytics and sales; replying to reviews and editing keywords need Customer Support / App Manager. The key is stored in your Keychain and only sent to Apple.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for new data in the background", isOn: $agentOn)
                    .onChange(of: agentOn) { _, on in
                        do { try BackgroundAgent.setEnabled(on) } catch { status = error.localizedDescription; agentOn = BackgroundAgent.isEnabled }
                    }
                Text("Every 6 hours, even when Almanac is closed. You'll get a notification when something needs attention.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let status { Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
                Spacer()
                if model.isDemo == false && !creds.isComplete { Button("Show demo data") { model.loadDemo() } }
                Button("Save and connect") { Task { await save() } }.keyboardShortcut(.defaultAction).disabled(!creds.isComplete || testing)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            creds.privateKeyPEM = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            // AuthKey_<KEYID>.p8 → fill the key ID for free.
            if creds.keyId.isEmpty, let m = url.lastPathComponent.firstMatch(of: #/AuthKey_([A-Z0-9]+)\.p8/#) { creds.keyId = String(m.1) }
        }
    }

    private func save() async {
        testing = true; defer { testing = false }
        do {
            _ = try await ASCClient(credentials: creds).json("v1/apps", query: ["limit": "1"])
            Keychain.save(creds)
            status = "Connected. Importing your data…"
            await model.refresh()
            status = model.syncErrors.isEmpty ? "All set." : model.syncErrors.joined(separator: "\n")
        } catch { status = error.localizedDescription }
    }
}

struct AISettingsView: View {
    @AppStorage("aiProvider") private var provider = Assistant.Provider.claude.rawValue
    @AppStorage("aiModel") private var aiModel = "sonnet"
    @State private var installed: Bool?

    var body: some View {
        Form {
            Picker("Use", selection: $provider) {
                ForEach(Assistant.Provider.allCases) { Text($0.title).tag($0.rawValue) }
            }
            if provider == Assistant.Provider.claude.rawValue {
                TextField("Model", text: $aiModel, prompt: Text("sonnet, opus, haiku…"))
            }
            LabeledContent("Status") {
                switch installed {
                case .some(true): Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .some(false): Label("Not found in your shell's PATH", systemImage: "xmark.circle").foregroundStyle(.red)
                case nil: ProgressView().controlSize(.small)
                }
            }
            Text("Almanac runs the command-line tool you already use, signed in with your own subscription. No API key, and nothing goes through a third-party server.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task(id: provider) { installed = nil; installed = await AISettings.assistant.isInstalled() }
    }
}
