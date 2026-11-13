#if os(macOS)
import AlmanacCore
import AppKit
import SwiftUI

/// Building blocks shared by Settings and the onboarding: titled card groups, rows, text fields.
protocol SettingsBlocks {}

extension SettingsBlocks {
    func group<C: View>(_ t: AlmanacTheme, _ title: String, _ caption: String? = nil, footer: String? = nil, @ViewBuilder _ rows: () -> C) -> some View {
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

    func row<C: View>(_ t: AlmanacTheme, _ label: String, _ detail: String? = nil, warn: Bool = false, @ViewBuilder _ control: () -> C) -> some View {
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

    func input(_ t: AlmanacTheme, _ text: Binding<String>, _ prompt: String, width: CGFloat = 220) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(t.label3))
            .textFieldStyle(.plain).font(t.font(12)).monospacedDigit()
            .padding(.horizontal, 8).frame(width: width, height: 26)
            .background(t.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.sep2, lineWidth: 1))
    }
}

/// The four theme miniatures; picking one switches the whole app.
struct ThemePicker: View {
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.nocturne.id
    var body: some View {
        let t = AlmanacTheme.named(themeId)
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
}

/// Issuer ID, key ID, .p8 (chosen or dropped anywhere on the form), vendor number, then a checked save.
struct ConnectForm: View, SettingsBlocks {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.nocturne.id
    var caption: String? = "Create a key with the Sales and Reports role in Users and Access → Integrations."
    /// Called once the key is checked and saved, before the import finishes.
    var onConnected: () -> Void = {}
    @State private var creds = Keychain.credentials()
    @State private var status: (text: String, error: Bool)?
    @State private var testing = false
    @State private var importing = false
    @State private var dropping = false
    @State private var showingQR = false

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        let saved = Keychain.credentials()
        let dirty = creds != saved
        group(t, "", caption) {
            row(t, "Issuer ID") { input(t, $creds.issuerId, "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", width: 300) }
            row(t, "Key ID") { input(t, $creds.keyId, "e.g. 2X9R4HXF34") }
            row(t, "Private key", creds.privateKeyPEM.isEmpty ? "Drop the AuthKey .p8 file here, or choose it." : nil) {
                if !creds.privateKeyPEM.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(creds.keyId.isEmpty ? "Loaded" : "AuthKey_\(creds.keyId).p8").font(t.font(12))
                        Text(dirty ? "Saved when you connect" : "Stored in your Keychain").font(t.font(11)).foregroundStyle(t.label2)
                    }
                }
                SmallButton(label: "Choose File…") { importing = true }
            }
            .background(dropping ? t.accentSoft : .clear)
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
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "p8" }) else { return false }
            AccountSettings.load(url, into: &creds)
            return true
        } isTargeted: { dropping = $0 }
        .fileImporter(isPresented: $importing, allowedContentTypes: AccountSettings.keyTypes) { result in
            if case .success(let url) = result { AccountSettings.load(url, into: &creds) }
        }
        .sheet(isPresented: $showingQR) { SetupQR(url: SetupLink.url(for: Keychain.credentials())) }
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

    private func save() async {
        testing = true; defer { testing = false }
        status = nil
        do {
            _ = try await ASCClient(credentials: creds).json("v1/apps", query: ["limit": "1"])
            Keychain.save(creds)
            status = ("Connected. Importing your data…", false)
            onConnected()
            await model.refresh()
            status = model.syncErrors.isEmpty ? nil : (model.syncErrors.joined(separator: "\n"), true)
        } catch { status = (error.localizedDescription, true) }
    }
}

/// Background refresh and insight notifications.
struct RefreshSettings: View, SettingsBlocks {
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.nocturne.id
    @AppStorage("notifyInsights") private var notify = true
    @State private var agentOn = BackgroundAgent.isEnabled
    @State private var error: String?
    var title = "Refresh"

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        group(t, title) {
            row(t, "Refresh in the background", error ?? "Every 6 hours, even when the window is closed. Listed in Login Items.", warn: error != nil) {
                Toggle("", isOn: $agentOn).labelsHidden().toggleStyle(.switch)
                    .onChange(of: agentOn) { _, on in
                        do { try BackgroundAgent.setEnabled(on); error = nil } catch { self.error = error.localizedDescription; agentOn = BackgroundAgent.isEnabled }
                    }
            }
            row(t, "Notify me about new insights", "Milestones and anything that needs attention, found by a background refresh.") {
                Toggle("", isOn: $notify).labelsHidden().toggleStyle(.switch).disabled(!agentOn)
            }
        }
    }
}

/// A miniature window in a theme's own colors: sidebar (or Ticker's rail), a hero number, two cards.
struct ThemePreview: View {
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
struct Separated: _VariadicView_MultiViewRoot {
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
