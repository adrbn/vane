import AlmanacCore
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// First launch: pick a look (Color Blocks preselected), then connect with the Mac's code, your own key, or the demo.
struct WelcomeFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var path: [WelcomeStep] = []
    enum WelcomeStep: Hashable { case scan, key }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vane").font(t.font(40, .heavy)).tracking(-1)
                        Text("Your App Store Connect numbers, read for you.").font(t.font(17)).foregroundStyle(t.label2)
                    }
                    .padding(.top, 24)
                    PhoneSectionTitle(title: "Choose a look", detail: "You can change it in Settings")
                    PhoneThemeGrid()
                    Spacer(minLength: 12)
                    PhoneButton(label: "Scan the Code on Your Mac") { path.append(.scan) }
                    PhoneButton(label: "Use My Own API Key", prominent: false) { path.append(.key) }
                    Button("Try the demo") { finish() }
                        .font(t.font(15, .semibold)).foregroundStyle(t.accentText)
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(t.label)
            .background(ThemeBackground().ignoresSafeArea())
            .navigationDestination(for: WelcomeStep.self) { s in
                switch s {
                case .scan: PhoneScan { finish() }
                case .key: PushedScreen(title: "Without a Mac", subtitle: "Connect with an App Store Connect API key") { PhoneKeyForm { finish() } }
                }
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        if !Keychain.credentials().isComplete && model.apps.isEmpty { model.loadDemo() }
        withAnimation { model.onboardingOpen = false }
    }
}

/// The four looks, two by two.
struct PhoneThemeGrid: View {
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.blocks.id
    @Environment(\.theme) private var t
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(AlmanacTheme.all, id: \.id) { theme in
                let on = theme.id == themeId
                Button { withAnimation(.snappy) { themeId = theme.id } } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ThemePreview(theme: theme)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? t.accent : t.sep2, lineWidth: on ? 2.5 : 1))
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(theme.name).font(t.font(14, .semibold))
                                Text(theme.scheme == .dark ? "Dark" : "Light").font(t.font(12)).foregroundStyle(t.label2)
                            }
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).foregroundStyle(on ? t.accent : t.label3)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Scans the `vane://setup` QR code shown by Vane on the Mac (Settings → Show Setup Code).
struct PhoneScan: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var done: () -> Void
    @State private var found: ASCCredentials?

    var body: some View {
        PushedScreen(title: "Scan code", subtitle: "On your Mac: Vane → Settings → Show Setup Code") {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRScanner { if found == nil, let url = URL(string: $0) { found = SetupLink.credentials(from: url) } }
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: t.phoneRadius, style: .continuous))
            } else {
                Text("This device can't scan. Point the iPhone's Camera at the code instead, or use your own key.")
                    .font(t.font(14)).foregroundStyle(t.label2).phoneCard()
            }
        }
        .alert("Connect to App Store Connect?", isPresented: Binding(get: { found != nil }, set: { if !$0 { found = nil } }), presenting: found) { c in
            Button("Connect") {
                Keychain.save(c)
                Task { await model.refresh() }
                done()
            }
            Button("Cancel", role: .cancel) {}
        } message: { c in Text("Use key \(c.keyId) from your Mac.") }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items { if let v = b.payloadStringValue, v.hasPrefix("vane://") { onCode(v) } }
        }
    }
}

/// Issuer ID, Key ID, .p8 file and vendor number; checked against App Store Connect before saving to the Keychain.
struct PhoneKeyForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var done: () -> Void = {}
    @State private var creds = Keychain.credentials()
    @State private var importing = false
    @State private var busy = false
    @State private var status: (text: String, error: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In App Store Connect: Users and Access → Integrations → App Store Connect API. The key needs the Sales and Reports role.")
                .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                input("Issuer ID", $creds.issuerId, "xxxxxxxx-xxxx-…")
                Divider().overlay(t.sep).padding(.leading, 16)
                input("Key ID", $creds.keyId, "2X9R4HXF34")
                Divider().overlay(t.sep).padding(.leading, 16)
                HStack {
                    Text("Private key").font(t.font(15))
                    Spacer()
                    Button(creds.privateKeyPEM.isEmpty ? "Choose .p8 File" : "AuthKey loaded") { importing = true }
                        .font(t.font(15, .semibold)).foregroundStyle(t.accentText)
                }
                .padding(.horizontal, 16).frame(height: 50)
                Divider().overlay(t.sep).padding(.leading, 16)
                input("Vendor number", $creds.vendorNumber, "87654321")
            }
            .phoneCard(padding: 0)
            if let status { Text(status.text).font(t.font(12)).foregroundStyle(status.error ? t.neg : t.label2) }
            PhoneButton(label: busy ? "Checking…" : "Connect") { Task { await connect() } }
                .disabled(!creds.isComplete || busy).opacity(creds.isComplete ? 1 : 0.5)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: AccountSettings.keyTypes) { r in
            if case .success(let url) = r { AccountSettings.load(url, into: &creds) }
        }
    }

    private func input(_ label: String, _ text: Binding<String>, _ prompt: String) -> some View {
        HStack {
            Text(label).font(t.font(15))
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(t.label3))
                .multilineTextAlignment(.trailing).font(t.font(15)).monospacedDigit()
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(.horizontal, 16).frame(height: 50)
    }

    private func connect() async {
        busy = true; defer { busy = false }
        status = nil
        do {
            _ = try await ASCClient(credentials: creds).json("v1/apps", query: ["limit": "1"])
            Keychain.save(creds)
            status = ("Connected. Importing your data…", false)
            done()
            await model.refresh()
        } catch { status = (error.localizedDescription, true) }
    }
}

/// Settings: connection, key, look.
struct PhoneSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        let connected = Keychain.credentials().isComplete
        PushedScreen(title: "Settings", subtitle: "") {
            PhoneSectionTitle(title: "Connection")
            HStack(spacing: 10) {
                Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 18)).foregroundStyle(connected ? t.pos : t.label3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connected ? "Connected" : model.isDemo ? "Showing demo data" : "Not connected").font(t.font(15, .semibold))
                    Text(model.lastSync.map { "Updated \($0.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))" } ?? "Scan the code from your Mac, or add a key below")
                        .font(t.font(12)).foregroundStyle(t.label2)
                }
                Spacer()
                if connected {
                    Button { Task { await model.refresh() } } label: {
                        if model.syncing { ProgressView() } else { Text("Refresh").font(t.font(14, .semibold)).foregroundStyle(t.accentText) }
                    }
                    .disabled(model.syncing)
                }
            }
            .phoneCard(padding: 14)
            PhoneSectionTitle(title: "Your API key")
            PhoneKeyForm()
            PhoneSectionTitle(title: "Look")
            PhoneThemeGrid()
        }
    }
}

/// Ask runs Claude Code or Codex on the Mac, so the phone explains where to find it.
struct AskScreen: View {
    @Environment(\.theme) private var t
    var body: some View {
        PhoneScreen(title: "Ask", subtitle: "Questions about your numbers") {
            VStack(alignment: .leading, spacing: 12) {
                IconSquare(symbol: "sparkles", style: t.square(.insights), size: 44)
                Text("Ask works through your Mac").font(t.font(22, .bold))
                Text("Vane answers with the Claude Code or Codex command line installed on your Mac. Open Vane on the Mac and ask there: it sees the same numbers as this iPhone.")
                    .font(t.font(15)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Why did downloads drop last week?", "Which country should I localize for next?", "Did the last release change conversion?"], id: \.self) {
                        Text($0).font(t.font(14)).foregroundStyle(t.label2)
                            .padding(.horizontal, 14).frame(height: 40, alignment: .leading)
                            .background(t.fill, in: Capsule())
                    }
                }
                .padding(.top, 4)
            }
            .phoneCard(padding: 20)
        }
    }
}
