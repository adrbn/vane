#if os(macOS)
import AlmanacCore
import AppKit
import SwiftUI

/// Mac Settings, shown as a sheet inside the main window: themes with previews, App Store Connect, Refresh, Assistant, Data.
struct MacSettingsView: View, SettingsBlocks {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.nocturne.id
    @AppStorage("aiProvider") private var provider = Assistant.Provider.claude.rawValue
    @AppStorage("aiModel") private var aiModel = "sonnet"
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
        .task(id: provider) { cli = nil; cli = .some(await AISettings.assistant.location()) }
    }

    // MARK: Sections

    private func page(_ t: AlmanacTheme) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            switch tab {
            case .general:
                group(t, "Appearance") { ThemePicker() }
                RefreshSettings()
            case .account: ConnectForm()
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
                row(t, "Sample data", "Opens a second Vane with demo apps and every metric filled in. Your data isn't touched.") {
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

    private var storeSize: String {
        let dir = (Store.defaultPath as NSString).deletingLastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let bytes = files.compactMap { try? FileManager.default.attributesOfItem(atPath: dir + "/" + $0)[.size] as? Int64 }.reduce(0, +)
        return bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US")))
    }

}
#endif
