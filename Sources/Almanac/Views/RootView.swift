import AlmanacCore
import SwiftUI

#if os(iOS)
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if model.isDemo { DemoBanner() }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id("\(model.appId ?? "")-\(model.revision)")
            }
            .navigationTitle(model.app?.name ?? "Almanac")
            .navigationSubtitle(title)
        }
        .inspector(isPresented: $model.chatOpen) {
            ChatPanel().inspectorColumnWidth(min: 300, ideal: 360, max: 520)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.refresh() } } label: {
                    if model.syncing { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .help(model.syncing ? model.syncStatus : "Fetch the latest data from App Store Connect")
                .disabled(model.syncing)
            }
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Button { model.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button { model.chatOpen.toggle() } label: { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
                    .help("Ask about what's on screen")
            }
        }
    }

    private var title: String {
        switch model.section {
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

    @ViewBuilder private var detail: some View {
        if model.app == nil {
            EmptyHint(title: "No apps yet", message: "Add your App Store Connect key in Settings, then refresh.", symbol: "app.dashed")
        } else {
            switch model.section {
            case .insights: LegacyInsightsView()
            case .listing: ListingView()
            case .reviews: ReviewsView()
            case .appStore: OverviewView(kind: .appStore)
            case .usage: OverviewView(kind: .usage)
            case .sales: SalesView()
            case .territories: LegacyTerritoriesView()
            case .metric(let m): LegacyMetricDetailView(metric: m)
            }
        }
    }
}

#endif

struct DemoBanner: View {
    @Environment(AppModel.self) private var model
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #else
    private func openSettings() { model.settingsOpen = true }
    #endif
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text("You're looking at demo data for three made-up apps.")
            Spacer()
            Button("Connect App Store Connect…") { openSettings() }.controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.yellow.opacity(0.14))
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // ponytail: plain buttons, List(selection:) never selected anything on macOS 27 (no highlight, no clicks).
        List {
            Section {
                row("Insights", "lightbulb", .insights, badge: model.store.insights(model.appId ?? "").filter(\.needsAttention).count)
                row("Listing", "text.page", .listing)
                row("Reviews", "text.bubble", .reviews)
            }
            Section("Analytics") {
                row("App Store", "bag", .appStore)
                row("Sales", "creditcard", .sales)
                row("Usage", "person.2", .usage)
                row("Territories", "globe.europe.africa", .territories)
            }
            if !model.pinned.isEmpty {
                Section("Pinned charts") {
                    ForEach(model.pinned) { m in
                        row(m.title, "chart.xyaxis.line", .metric(m))
                            .contextMenu { Button("Unpin") { model.togglePin(m) } }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) { AppSwitcher().padding(.horizontal, 10).padding(.bottom, 4) }
        .safeAreaInset(edge: .bottom) { SyncFooter() }
    }

    private func row(_ title: String, _ symbol: String, _ s: Pane, badge: Int = 0) -> some View {
        let on = model.section == s
        return Button { model.section = s } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fontWeight(on ? .semibold : .regular)
        .badge(badge)
        .listRowBackground(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(on ? Color.primary.opacity(0.09) : .clear).padding(.horizontal, 10))
    }
}

struct AppSwitcher: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Menu {
            ForEach(model.apps) { app in
                Button { model.appId = app.id } label: { Text(app.name) }
            }
        } label: {
            HStack(spacing: 8) {
                if let app = model.app { AppIconView(app: app, size: 26) }
                Text(model.app?.name ?? "No app").font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

struct SyncFooter: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.syncing {
                Text(model.syncStatus).lineLimit(1)
            } else if let d = model.lastSync {
                Text("Updated \(d.formatted(.relative(presentation: .named)))")
            }
            if !model.syncErrors.isEmpty {
                Label("\(model.syncErrors.count) problem\(model.syncErrors.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(model.syncErrors.joined(separator: "\n"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
