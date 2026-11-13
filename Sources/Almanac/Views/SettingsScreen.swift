#if os(macOS)
import AlmanacCore
import AppKit
import SwiftUI

/// Mac Settings, shown as a sheet inside the main window: themes with previews, App Store Connect, Refresh, Assistant, Data.
struct MacSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.nocturne.id
    @AppStorage("aiProvider") private var provider = Assistant.Provider.claude.rawValue
    @AppStorage("aiModel") private var aiModel = "sonnet"
    @AppStorage("notifyInsights") private var notify = true
    @State private var creds = Keychain.credentials()
    @State private var status: (text: String, error: Bool)?
    @State private var testing = false
    @State private var importing = false
    @State private var showingQR = false
    @State private var agentOn = BackgroundAgent.isEnabled
    @State private var cli: String??
    @State private var tab: Tab = Keychain.credentials().isComplete ? .general : .account

    enum Tab: String, CaseIterable { case general = "General", account = "App Store Connect", assistant = "Assistant", data = "Data" }

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(t.font(20, .bold))
                Spacer()
                SmallButton(label: "Done", prominent: true) { model.settingsOpen = false }
                    .keyboardShortcut(.cancelAction)
            }
            GlassSegments(options: Tab.allCases.map { ($0, $0.rawValue) }, selection: $tab.animation(.easeOut(duration: 0.2)))
            // Sized to the tab's content so short tabs don't leave an empty sheet; scrolls only when the window is too short.
            ViewThatFits(in: .vertical) {
                page(t)
                ScrollView { page(t) }.scrollIndicators(.never)
            }
        }
        .foregroundStyle(t.label)
        .font(t.font(13))
        .tint(t.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: AccountSettings.keyTypes) { result in
            if case .success(let url) = result { AccountSettings.load(url, into: &creds) }
        }
        .sheet(isPresented: $showingQR) { SetupQR(url: SetupLink.url(for: Keychain.credentials())) }
        .task(id: provider) { cli = nil; cli = .some(await AISettings.assistant.location()) }
    }

    // MARK: Sections

    private func page(_ t: AlmanacTheme) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            switch tab {
            case .general:
                group(t, "Appearance") { themes(t) }
                refresh(t)
            case .account: connect(t)
            case .assistant: assistant(t)
            case .data: data(t)
            }
        }
        .padding(.bottom, 4)
    }

    private func data(_ t: AlmanacTheme) -> some View {
        group(t, "") {
            row(t, "Stored on this Mac · \(storeSize)", (Store.defaultPath as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                SmallButton(label: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Store.defaultPath)]) }
            }
            if !model.isDemo {
                row(t, "Sample data", "Opens a second Almanac with demo apps and every metric filled in. Your data isn't touched.") {
                    SmallButton(label: "Open Demo Window") {
                        let config = NSWorkspace.OpenConfiguration()
                        config.createsNewApplicationInstance = true
                        config.arguments = ["--demo"]
                        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
                    }
                }
            }
        }
    }

    private func connect(_ t: AlmanacTheme) -> some View {
        let saved = Keychain.credentials()
        let dirty = creds != saved
        return group(t, "", "Create a key with the Sales and Reports role in Users and Access → Integrations.") {
            row(t, "Issuer ID") { input(t, $creds.issuerId, "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", width: 300) }
            row(t, "Key ID") { input(t, $creds.keyId, "e.g. 2X9R4HXF34") }
            row(t, "Private key") {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(creds.privateKeyPEM.isEmpty ? "None" : creds.keyId.isEmpty ? "Loaded" : "AuthKey_\(creds.keyId).p8").font(t.font(12))
                    if !creds.privateKeyPEM.isEmpty { Text(dirty ? "Saved when you connect" : "Stored in your Keychain").font(t.font(11)).foregroundStyle(t.label2) }
                }
                SmallButton(label: "Choose File…") { importing = true }
            }
            row(t, "Vendor number") { input(t, $creds.vendorNumber, "e.g. 87654321") }
            HStack(spacing: 8) {
                Image(systemName: status?.error == true ? "xmark.circle.fill" : saved.isComplete && !dirty ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 15)).foregroundStyle(status?.error == true ? t.neg : saved.isComplete && !dirty ? t.pos : t.label3)
                connectionText(t, saved: saved, dirty: dirty)
                Spacer(minLength: 8)
                if !model.isDemo && !creds.isComplete { SmallButton(label: "Show Demo Data") { model.loadDemo() } }
                SmallButton(label: testing ? "Checking…" : dirty ? "Save and Connect" : "Test Connection", prominent: dirty, busy: testing) { Task { await save() } }
                    .disabled(!creds.isComplete).opacity(!creds.isComplete ? 0.5 : 1)
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            if saved.isComplete {
                row(t, "Vane on iPhone", "Shows a QR code the iPhone's Camera can scan to connect with this key.") {
                    SmallButton(label: "Show Setup Code…") { showingQR = true }
                }
            }
        }
    }

    private func connectionText(_ t: AlmanacTheme, saved: ASCCredentials, dirty: Bool) -> some View {
        let text: Text
        if let status {
            text = Text(status.text)
        } else if !saved.isComplete {
            text = Text("Not connected").font(t.font(12, .semibold)) + Text(" · add your key to import your data").foregroundStyle(t.label2)
        } else if dirty {
            text = Text("Unsaved changes").font(t.font(12, .semibold))
        } else {
            let when = model.lastSync.map { " · updated \($0.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))" } ?? ""
            text = Text("Connected").font(t.font(12, .semibold)) + Text("\(when) · \(model.apps.count) app\(model.apps.count == 1 ? "" : "s")").foregroundStyle(t.label2)
        }
        return text.font(t.font(12)).foregroundStyle(status?.error == true ? t.neg : t.label).lineLimit(2)
    }

    private func refresh(_ t: AlmanacTheme) -> some View {
        group(t, "Refresh") {
            row(t, "Refresh in the background", "Every 6 hours, even when the window is closed. Listed in Login Items.") {
                Toggle("", isOn: $agentOn).labelsHidden().toggleStyle(.switch)
                    .onChange(of: agentOn) { _, on in
                        do { try BackgroundAgent.setEnabled(on) } catch { status = (error.localizedDescription, true); agentOn = BackgroundAgent.isEnabled }
                    }
            }
            row(t, "Notify me about new insights", "Milestones and anything that needs attention, found by a background refresh.") {
                Toggle("", isOn: $notify).labelsHidden().toggleStyle(.switch).disabled(!agentOn)
            }
        }
    }

    private func assistant(_ t: AlmanacTheme) -> some View {
        let p = Assistant.Provider(rawValue: provider) ?? .claude
        let found: String = switch cli {
        case .none: "Looking for \(p.rawValue)…"
        case .some(.none): "\(p.title) isn't in your shell's PATH"
        case .some(.some(let path)): "\(p.title) at \(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
        }
        return group(t, "", nil, footer: "Raw reports and your private key never leave this Mac. The assistant runs your own command-line tool and only sees the numbers on the screen you ask about.") {
            row(t, "Provider", found, warn: cli == .some(nil)) {
                GlassSegments(options: Assistant.Provider.allCases.map { ($0.rawValue, $0 == .claude ? "Claude" : "Codex CLI") }, selection: $provider)
            }
            if p == .claude {
                row(t, "Model", "sonnet, opus or haiku") { input(t, $aiModel, "sonnet", width: 140) }
            }
        }
    }

    private func themes(_ t: AlmanacTheme) -> some View {
        HStack(spacing: 12) {
            ForEach(AlmanacTheme.all, id: \.id) { theme in
                let on = theme.id == themeId
                Button { themeId = theme.id } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ThemePreview(theme: theme)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? t.accent : t.sep2, lineWidth: on ? 2 : 1))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(theme.name).font(t.font(12, .semibold)).foregroundStyle(on ? t.label : t.label2)
                            Text(theme.scheme == .dark ? "Dark" : "Light").font(t.font(11)).foregroundStyle(t.label3)
                        }
                        .padding(.horizontal, 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(theme.name)
            }
        }
        .padding(12)
    }

    // MARK: Building blocks

    private func group<C: View>(_ t: AlmanacTheme, _ title: String, _ caption: String? = nil, footer: String? = nil, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // A tab holding a single group passes no title: the tab already names it.
            if !title.isEmpty || caption != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if !title.isEmpty { Text(title).font(t.font(15, .bold)) }
                    if let caption { Text(caption).font(t.font(11)).foregroundStyle(t.label2) }
                }
                .padding(.horizontal, 4)
            }
            // Smaller than the sheet's radius: these cards sit 24 pt inside it, so the same radius looks swollen.
            _VariadicView.Tree(Separated(sep: t.sep)) { rows() }
                .themedCard(padding: 0, radius: t.rS + 2)
            if let footer { Text(footer).font(t.font(11)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4) }
        }
    }

    private func row<C: View>(_ t: AlmanacTheme, _ label: String, _ detail: String? = nil, warn: Bool = false, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(t.font(13, .semibold))
                if let detail { Text(detail).font(t.font(11)).foregroundStyle(warn ? t.warn : t.label2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 44)
    }

    private func input(_ t: AlmanacTheme, _ text: Binding<String>, _ prompt: String, width: CGFloat = 220) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(t.label3))
            .textFieldStyle(.plain).font(t.font(12)).monospacedDigit()
            .padding(.horizontal, 8).frame(width: width, height: 26)
            .background(t.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.sep2, lineWidth: 1))
    }

    private var storeSize: String {
        let dir = (Store.defaultPath as NSString).deletingLastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let bytes = files.compactMap { try? FileManager.default.attributesOfItem(atPath: dir + "/" + $0)[.size] as? Int64 }.reduce(0, +)
        return bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US")))
    }

    private func save() async {
        testing = true; defer { testing = false }
        status = nil
        do {
            _ = try await ASCClient(credentials: creds).json("v1/apps", query: ["limit": "1"])
            Keychain.save(creds)
            status = ("Connected. Importing your data…", false)
            await model.refresh()
            status = model.syncErrors.isEmpty ? nil : (model.syncErrors.joined(separator: "\n"), true)
        } catch { status = (error.localizedDescription, true) }
    }
}

/// A miniature window in a theme's own colors: sidebar (or Ticker's rail), a hero number, two cards.
private struct ThemePreview: View {
    let theme: AlmanacTheme
    var body: some View {
        let t = theme
        HStack(spacing: 4) {
            if t.usesRail {
                VStack(spacing: 4) { ForEach(0..<4, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(i == 0 ? t.navSel : t.label3.opacity(0.5)).frame(width: 8, height: 8) } ; Spacer() }
                    .padding(.top, 10).frame(width: 16)
                    .overlay(alignment: .trailing) { t.sep.frame(width: 1) }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in Capsule().fill(i == 0 ? t.accent : t.label3.opacity(0.6)).frame(width: i == 0 ? 18 : 14, height: 3) }
                    Spacer()
                }
                .padding(6).padding(.top, 6).frame(width: 30, alignment: .leading).frame(maxHeight: .infinity)
                .background(t.side, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("7.3%").font(t.font(15, t.numWeight)).foregroundStyle(t.id == "blocks" || t.id == "candy" ? t.heroFg : t.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(t.heroPad > 0 ? 5 : 0)
                    .background(hero, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                HStack(spacing: 4) {
                    card(t.accent)
                    card(t.pos)
                }
            }
            .padding(.vertical, 8).padding(.trailing, 6).padding(.leading, t.usesRail ? 2 : 0)
        }
        .frame(height: 76)
        .background(ThemeBackground().environment(\.theme, t))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, t.scheme)
    }

    private var hero: AnyShapeStyle {
        switch theme.id {
        case "blocks": AnyShapeStyle(theme.accent)
        case "candy": AnyShapeStyle(LinearGradient(colors: [Color(css: "#6C5CFF"), Color(css: "#A44EF2"), Color(css: "#FF6EAE")], startPoint: .topLeading, endPoint: .bottomTrailing))
        default: AnyShapeStyle(Color.clear)
        }
    }

    private func card(_ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule().fill(theme.label3).frame(width: 14, height: 2)
            Capsule().fill(c).frame(width: 20, height: 3)
        }
        .padding(5).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }
}

/// Puts a hairline between the rows of a settings group.
private struct Separated: _VariadicView_MultiViewRoot {
    var sep: Color
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != children.last?.id { Rectangle().fill(sep).frame(height: 1).padding(.leading, 12) }
            }
        }
    }
}
#endif
