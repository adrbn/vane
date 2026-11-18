import AlmanacCore
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// First launch: what Vane is, then one way in: the Mac's code, your own key, or the demo. The look waits in Settings.
struct WelcomeFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var path: [WelcomeStep] = []
    enum WelcomeStep: Hashable { case scan, key }

    var body: some View {
        NavigationStack(path: $path) {
            // One scale: 8 / 16 / 24 / 32 spacing, 24 pt sides, text 34 / 17 / 15 / 13. Pitch on top, choices pinned to the bottom.
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        VaneIcon(size: 64).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vane").font(t.font(34, .heavy)).tracking(-0.5)
                            Text("Your App Store Connect numbers, read for you.")
                                .font(t.font(17)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        point("lightbulb.fill", .insights, "Insights", "Milestones, drops and keyword issues, spotted for you.")
                        point("chart.xyaxis.line", .appstore, "Every metric", "Downloads, conversion, sales and sessions.")
                        point("text.bubble.fill", .reviews, "Reviews and listing", "Answer reviews and fix your metadata.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    PhoneButton(label: String(localized: "Scan the Code on Your Mac")) { path.append(.scan) }
                    PhoneButton(label: String(localized: "Enter an API Key"), prominent: false) { path.append(.key) }
                    Button { finish() } label: {
                        Text("Try the Demo").font(t.font(17, .semibold)).foregroundStyle(t.accentText)
                            .frame(maxWidth: .infinity).frame(height: 54).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("Vane on the Mac shows the code in Settings → App Store Connect.")
                        .font(t.font(13)).foregroundStyle(t.label2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
                .background(ThemeBackground().ignoresSafeArea())
            }
            .foregroundStyle(t.label)
            .background(ThemeBackground().ignoresSafeArea())
            .navigationDestination(for: WelcomeStep.self) { s in
                switch s {
                case .scan: PhoneScan { finish() }
                case .key: PushedScreen(title: String(localized: "API key"), subtitle: String(localized: "The same key Vane uses on the Mac")) { PhoneKeyForm { finish() } }
                }
            }
        }
    }

    private func point(_ symbol: String, _ section: AlmanacTheme.Section, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            IconSquare(symbol: symbol, style: t.square(section), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(t.font(17, .semibold))
                Text(text).font(t.font(15)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
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
                                Text(theme.scheme == .dark ? String(localized: "Dark") : String(localized: "Light")).font(t.font(12)).foregroundStyle(t.label2)
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
        PushedScreen(title: String(localized: "Scan code"), subtitle: String(localized: "On the Mac: Vane → Settings → App Store Connect → Show Setup Code")) {
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
                input(String(localized: "Issuer ID"), $creds.issuerId, "xxxxxxxx-xxxx-…")
                Divider().overlay(t.sep).padding(.leading, 16)
                input(String(localized: "Key ID"), $creds.keyId, "2X9R4HXF34")
                Divider().overlay(t.sep).padding(.leading, 16)
                HStack {
                    Text("Private key").font(t.font(15))
                    Spacer()
                    Button(creds.privateKeyPEM.isEmpty ? String(localized: "Choose .p8 File") : String(localized: "AuthKey loaded")) { importing = true }
                        .font(t.font(15, .semibold)).foregroundStyle(t.accentText)
                }
                .padding(.horizontal, 16).frame(height: 50)
                Divider().overlay(t.sep).padding(.leading, 16)
                input(String(localized: "Vendor number"), $creds.vendorNumber, "87654321")
            }
            .phoneCard(padding: 0)
            if let status { Text(status.text).font(t.font(12)).foregroundStyle(status.error ? t.neg : t.label2) }
            PhoneButton(label: busy ? String(localized: "Checking…") : String(localized: "Connect")) { Task { await connect() } }
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
            status = (String(localized: "Connected. Importing your data…"), false)
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
        PushedScreen(title: String(localized: "Settings"), subtitle: "") {
            PhoneSectionTitle(title: String(localized: "Connection"))
            HStack(spacing: 10) {
                Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 18)).foregroundStyle(connected ? t.pos : t.label3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connected ? String(localized: "Connected") : model.isDemo ? String(localized: "Showing demo data") : String(localized: "Not connected")).font(t.font(15, .semibold))
                    Text(model.lastSync.map { String(localized: "Updated \($0.formatted(.relative(presentation: .named).locale(.current)))") } ?? String(localized: "Scan the code from your Mac, or add a key below"))
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
            if !model.syncErrors.isEmpty {
                Text(model.syncErrors.joined(separator: "\n")).font(t.font(12)).foregroundStyle(t.warn)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).phoneCard(padding: 14)
            }
            PhoneSectionTitle(title: String(localized: "Your API key"))
            PhoneKeyForm()
            PhoneSectionTitle(title: String(localized: "Look"))
            PhoneThemeGrid()
            PhoneSectionTitle(title: String(localized: "Language"))
            // iOS keeps a per-app language in its own Settings, with every language Vane ships.
            Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: {
                HStack {
                    Text(Locale.current.localizedString(forIdentifier: Bundle.main.preferredLocalizations.first ?? "en")?.localizedCapitalized ?? "").font(t.font(15))
                    Spacer()
                    Text("Change in iOS Settings").font(t.font(14, .semibold)).foregroundStyle(t.accentText)
                }
                .phoneCard(padding: 14)
            }
            .buttonStyle(.plain)
            PhoneSectionTitle(title: String(localized: "Insights"), detail: String(localized: "Fixed rules, no AI"))
            @Bindable var m = model
            VStack(spacing: 0) {
                ForEach(Array(InsightCategory.allCases.enumerated()), id: \.element) { i, c in
                    if i > 0 { Divider().overlay(t.sep).padding(.leading, 52) }
                    Toggle(isOn: Binding(get: { !m.mutedCategories.contains(c) },
                                         set: { on in if on { m.mutedCategories.remove(c) } else { m.mutedCategories.insert(c) } })) {
                        HStack(spacing: 12) {
                            IconSquare(symbol: c.symbol, style: t.square(c.section), size: 26)
                            Text(c.title).font(t.font(15))
                        }
                    }
                    .tint(t.accent)
                    .padding(.horizontal, 14).frame(height: 50)
                }
            }
            .phoneCard(padding: 0)
            NavigationLink(value: PhoneRoute.about) {
                HStack(spacing: 12) {
                    VaneIcon(size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("About Vane").font(t.font(15, .semibold))
                        Text("Version \(AboutView.version) · Source code · Ko-fi").font(t.font(12)).foregroundStyle(t.label2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.label3)
                }
                .phoneCard(padding: 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }
}

/// Ask runs Claude Code or Codex on the Mac, so the phone explains where to find it.
struct AskScreen: View {
    @Environment(\.theme) private var t
    var body: some View {
        PhoneScreen(title: String(localized: "Ask"), subtitle: String(localized: "Questions about your numbers")) {
            VStack(alignment: .leading, spacing: 12) {
                IconSquare(symbol: "sparkles", style: t.square(.insights), size: 44)
                Text("Ask works through your Mac").font(t.font(22, .bold))
                Text("Vane answers with the Claude Code or Codex command line installed on your Mac. Open Vane on the Mac and ask there: it sees the same numbers as this iPhone.")
                    .font(t.font(15)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach([String(localized: "Why did downloads drop last week?"), String(localized: "Which country should I localize for next?"), String(localized: "Did the last release change conversion?")], id: \.self) {
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
