#if os(macOS)
import AlmanacCore
import SwiftUI

/// Window shell: themed background, glass sidebar (or Ticker's icon rail), screen, inspector.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.nocturne.id

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        ZStack {
            ThemeBackground()
            HStack(spacing: 0) {
                if t.usesRail { IconRail() } else { ThemedSidebar() }
                VStack(spacing: 0) {
                    if model.isDemo { DemoBanner().clipShape(RoundedRectangle(cornerRadius: t.rS)).padding(.horizontal, 24).padding(.top, 8) }
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .id("\(model.appId ?? "")-\(model.revision)")
                }
                // A screen wider than its slot must never push the sidebar or the chat off the window.
                .frame(minWidth: 0)
                // Clipped with the screen, so the arrow slides out from behind the sidebar instead of over it.
                .overlay(alignment: model.swipeProgress < 0 ? .trailing : .leading) { SwipeArrow(progress: model.swipeProgress) }
                .clipped()
                if model.chatOpen {
                    InspectorPanel()
                        .frame(width: 304)
                        .background(t.side, in: RoundedRectangle(cornerRadius: t.r - 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: t.r - 4, style: .continuous).strokeBorder(t.sideBorder, lineWidth: 1))
                        .padding(8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .blur(radius: model.settingsOpen || model.onboardingOpen ? 32 : 0)
        .overlay {
            if model.onboardingOpen {
                CenteredSheet(width: 640, onDismiss: {}) { OnboardingView() }
                    .transition(.opacity)
            } else if model.settingsOpen {
                CenteredSheet(width: 640, onDismiss: { model.settingsOpen = false }) { MacSettingsView() }
                    .transition(.opacity)
            }
        }
        .background(WindowChrome())
        .ignoresSafeArea()
        .foregroundStyle(t.label)
        .font(t.font(13))
        .tint(t.accent)
        .environment(\.theme, t)
        .preferredColorScheme(t.scheme)
        .animation(.default, value: model.chatOpen)
        .animation(.easeOut(duration: 0.18), value: model.settingsOpen)
        .animation(.easeOut(duration: 0.18), value: model.onboardingOpen)
        .task { openLaunchReport(); SwipeNavigation.install(model) }
        .onChange(of: model.chatOpen) { _, open in ChatRoom.fit(open: open) }
    }

    @Environment(\.openWindow) private var openWindow

    /// `--report week|month|year` opens that report for the current app (screenshots).
    private func openLaunchReport() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--report"), let app = model.appId, let last = model.store.lastDay(app) else { return }
        let p = i + 1 < args.count ? ReportPeriod(rawValue: args[i + 1]) ?? .week : .week
        openWindow(id: "report", value: ReportRef(appId: app, period: p, start: ReportView.start(p, last)))
    }

    @ViewBuilder private var detail: some View {
        if model.app == nil {
            Screen(title: "Vane", subtitle: "") {} content: {
                EmptyHint(title: "No apps yet", message: "Add your App Store Connect key in Settings, then refresh.", symbol: "app.dashed")
            }
        } else {
            switch model.section {
            case .insights: InsightsView()
            case .listing: ListingView()
            case .reviews: ReviewsView()
            case .appStore: AppStoreView()
            case .usage: UsageScreen()
            case .sales: SalesScreen()
            case .territories: TerritoriesView()
            case .metric(let m): MetricDetailView(metric: m)
            }
        }
    }
}

extension Pane {
    var title: String {
        switch self {
        case .insights: "Insights"
        case .listing: "Listing"
        case .reviews: "Reviews"
        case .appStore: "App Store"
        case .sales: "Sales"
        case .usage: "Usage"
        case .territories: "Territories"
        case .metric(let m): m.title
        }
    }

    var symbol: String {
        switch self {
        case .insights: "lightbulb.fill"
        case .listing: "doc.text.fill"
        case .reviews: "text.bubble.fill"
        case .appStore: "bag.fill"
        case .sales: "dollarsign"
        case .usage: "waveform.path.ecg"
        case .territories: "globe"
        case .metric: "chart.xyaxis.line"
        }
    }

    var themeSection: AlmanacTheme.Section {
        switch self {
        case .insights: .insights
        case .listing: .listing
        case .reviews: .reviews
        case .appStore: .appstore
        case .sales: .sales
        case .usage: .usage
        case .territories: .territories
        case .metric(let m): m == .proceeds || m == .sales ? .sales : .appstore
        }
    }

    static let group1: [Pane] = [.insights, .listing, .reviews]
    static let analytics: [Pane] = [.appStore, .sales, .usage, .territories]
}

struct ThemedSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)   // traffic lights
            ThemedAppSwitcher()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Pane.group1, id: \.self) { row($0) }
                    header("Analytics")
                    ForEach(Pane.analytics, id: \.self) { row($0) }
                    header("Pinned charts")
                    if model.pinned.isEmpty {
                        Text("Pin any chart to keep it here.").font(t.font(12)).foregroundStyle(t.label2).padding(.horizontal, 8)
                    }
                    ForEach(model.pinned) { m in pinRow(m) }
                }
                .padding(.top, 12)
            }
            .scrollIndicators(.never)
            HStack(alignment: .center, spacing: 4) {
                ThemedSyncFooter()
                SettingsGear(size: 28)
            }
            .padding(8)
        }
        .padding([.horizontal, .bottom], 10)
        .frame(width: 224)
        .background(t.side, in: RoundedRectangle(cornerRadius: t.r - 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r - 4, style: .continuous).strokeBorder(t.sideBorder, lineWidth: 1))
        .shadow(color: t.hasShadow ? Color(css: "rgba(80,60,140,0.08)") : .clear, radius: 15, y: 8)
        .padding([.leading, .vertical], 8)
    }

    private func header(_ s: String) -> some View {
        Text(s).font(t.font(11, .bold)).foregroundStyle(t.label2)
            .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 6)
    }

    private func row(_ p: Pane) -> some View {
        let count = p == .reviews ? model.store.reviews(model.appId ?? "").filter { $0.response == nil && $0.rating <= 3 }.count : 0
        let dot = p == .insights && model.hasUnseenInsights
        return Button { model.section = p } label: {
            HStack(spacing: 10) {
                IconSquare(symbol: p.symbol, style: t.square(p.themeSection))
                Text(p.title).font(t.font(13, .semibold)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if count > 0 { Text("\(count)").font(t.font(12, .semibold)).foregroundStyle(t.label2).monospacedDigit() }
                if dot { UnseenDot() }
            }
            .padding(.horizontal, 6).frame(height: 34)
            .background(isOn(p) ? t.navSel : .clear, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pinRow(_ m: Metric) -> some View {
        Button { model.section = .metric(m) } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.label2).frame(width: 16)
                Text(m.title).font(t.font(13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10).padding(.trailing, 6).frame(height: 30)
            .background(model.section == .metric(m) ? t.navSel : .clear, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Unpin") { model.togglePin(m) } }
    }

    private func isOn(_ p: Pane) -> Bool { model.section == p }
}

struct ThemedAppSwitcher: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var body: some View {
        Menu {
            ForEach(model.apps) { app in Button(app.name) { model.appId = app.id } }
        } label: {
            HStack(spacing: 10) {
                if let app = model.app { AppIconView(app: app, size: 34) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.app?.name ?? "No app").font(t.font(14, .bold)).lineLimit(1)
                    Text(subtitle).font(t.font(11)).foregroundStyle(t.label2).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(t.label2)
            }
            .padding(.horizontal, 8).frame(height: 52)
            .background(t.fill, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }

    private var subtitle: String {
        guard let app = model.app else { return "" }
        return model.store.versions(app.id).last.map { "iOS · Version \($0.version)" } ?? "iOS"
    }
}

struct ThemedSyncFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.syncing {
                Text(model.syncStatus).foregroundStyle(t.label2).lineLimit(1)
            } else if let d = model.lastSync {
                Text("Updated \(d.formatted(.relative(presentation: .named)))").foregroundStyle(t.label2)
                Text("Next refresh in the background").foregroundStyle(t.label3).lineLimit(1).minimumScaleFactor(0.8)
            }
            if !model.syncErrors.isEmpty {
                Text("\(model.syncErrors.count) problem\(model.syncErrors.count == 1 ? "" : "s") with the last refresh")
                    .foregroundStyle(t.warn).help(model.syncErrors.joined(separator: "\n"))
            }
        }
        .font(t.font(11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { Button("Refresh Now") { Task { await model.refresh() } } }
    }
}

/// Opens Settings as a sheet inside the window.
struct SettingsGear: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var size: CGFloat
    var body: some View {
        Button { model.settingsOpen = true } label: {
            Image(systemName: "gearshape").font(.system(size: size > 30 ? 16 : 14, weight: .semibold))
                .foregroundStyle(t.label2)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
    }
}

/// Ticker: 80 pt rail of icons, no labels.
/// System red, like a Dock or Mail badge without a number: "something new here".
struct UnseenDot: View {
    var body: some View {
        Circle().fill(Color(nsColor: .systemRed)).frame(width: 8, height: 8)
            .accessibilityLabel("New insights")
    }
}

struct IconRail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: 48)   // traffic lights
            Menu {
                ForEach(model.apps) { app in Button(app.name) { model.appId = app.id } }
            } label: {
                if let app = model.app { AppIconView(app: app, size: 32) }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .padding(.bottom, 6)
            ForEach(Pane.group1 + Pane.analytics, id: \.self) { p in
                let on = model.section == p || (p == .appStore && { if case .metric = model.section { true } else { false } }())
                Button { model.section = p } label: {
                    Image(systemName: p.symbol).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(on ? Color.white : Color(css: "#8E8E93"))
                        .frame(width: 40, height: 40)
                        .background(on ? t.navSel : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) { if p == .insights && model.hasUnseenInsights { UnseenDot().padding(5) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.title)
            }
            Spacer()
            SettingsGear(size: 40).padding(.bottom, 12)
        }
        .frame(width: 92)
        .overlay(alignment: .trailing) { t.sep.frame(width: 1) }
    }
}
#endif

#if os(macOS)
import AppKit

/// Gives the window an empty unified toolbar so the traffic lights sit 52 pt tall, inside the sidebar's rounded corner.
/// In full screen the toolbar is removed: there it would draw an opaque bar over the top of the content.
/// The chat panel takes room from the window, not from the screen: opening it widens the window
/// (as far as the display allows) so the screen keeps its width; closing it gives the width back.
@MainActor enum ChatRoom {
    static let panel: CGFloat = 320
    private static var grown: CGFloat = 0

    static func fit(open: Bool) {
        guard let w = NSApp.windows.first(where: { $0.title == "Vane" && $0.isVisible }), !w.styleMask.contains(.fullScreen), let screen = w.screen else { return }
        var f = w.frame
        let room = screen.visibleFrame
        if open {
            let add = min(panel, room.width - f.width)
            guard add > 0 else { return }
            f.size.width += add
            if f.maxX > room.maxX { f.origin.x = max(room.minX, room.maxX - f.width) }
            grown = add
        } else {
            guard grown > 0 else { return }
            f.size.width -= grown
            grown = 0
        }
        w.setFrame(f, display: true, animate: true)
    }
}

struct WindowChrome: NSViewRepresentable {
    final class Coordinator { var observers: [NSObjectProtocol] = [] }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window, w.toolbar == nil else { return }
            Self.install(w)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            let nc = NotificationCenter.default
            context.coordinator.observers = [
                nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: w, queue: .main) { _ in w.toolbar = nil },
                nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { _ in Self.install(w) },
            ]
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.observers.forEach(NotificationCenter.default.removeObserver)
    }

    private static func install(_ w: NSWindow) {
        let tb = NSToolbar(identifier: "almanac.main")
        tb.showsBaselineSeparator = false
        w.toolbar = tb
        w.toolbarStyle = .unified
    }
}
#endif

#if os(macOS)
/// Back/forward swipe feedback, as in browsers: an arrow bubble slides in from the edge and fills once the swipe will go through.
private struct SwipeArrow: View {
    @Environment(\.theme) private var t
    var progress: CGFloat
    var body: some View {
        let p = min(abs(progress), 1)
        let ready = p > 0.33          // ~where the system commits the swipe
        Image(systemName: progress < 0 ? "chevron.right" : "chevron.left")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(ready ? t.onAccent : t.label)
            .frame(width: 44, height: 44)
            .background(ready ? t.accent : t.card, in: Circle())
            .overlay(Circle().strokeBorder(t.sep2, lineWidth: ready ? 0 : 1))
            .scaleEffect(0.7 + 0.3 * min(p * 3, 1))
            .offset(x: (progress < 0 ? 1 : -1) * (56 - 76 * min(p * 3, 1)))
            .opacity(p == 0 ? 0 : 1)
            .animation(.snappy(duration: 0.15), value: ready)
            .allowsHitTesting(false)
    }
}
#endif
