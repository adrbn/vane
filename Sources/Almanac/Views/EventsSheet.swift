import AlmanacCore
import SwiftUI

/// Campaigns, promos, press: drawn on the charts next to releases, and read by the assistant and the MCP server.
struct EventsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var allApps = false

    var body: some View {
        let app = model.appId ?? ""
        let events = { _ = model.revision; return model.store.events(app).reversed() }()
        VStack(alignment: .leading, spacing: 16) {
            Text("Events").font(t.font(20, .bold))
            Text("A campaign, a sale, an article, a post that took off. Events show on the charts next to releases, and the assistant uses them to explain changes.")
                .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField(String(localized: "e.g. Spring sale, Reddit post"), text: $title).textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden().fixedSize()
                Toggle(String(localized: "All apps"), isOn: $allApps).fixedSize()
                SmallButton(label: String(localized: "Add"), prominent: true, action: add).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if events.isEmpty {
                Text("No events for \(model.app?.name ?? String(localized: "this app")) yet.").font(t.font(13)).foregroundStyle(t.label3)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(events) { e in
                            HStack(spacing: 12) {
                                Text(Day.date(e.day).formatted(.dateTime.day().month(.abbreviated).year())).font(t.font(12)).foregroundStyle(t.label2)
                                    .monospacedDigit().frame(width: 96, alignment: .leading)
                                Text(e.title).font(t.font(13, .semibold))
                                if e.appId.isEmpty { Text("All apps").font(t.font(11)).foregroundStyle(t.label2) }
                                Spacer()
                                Button { try? model.store.delete(event: e.id); model.revision += 1 } label: {
                                    Image(systemName: "trash").foregroundStyle(t.label3)
                                }
                                .buttonStyle(.plain).help("Delete")
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { t.sep.frame(height: 1) }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
            HStack { Spacer(); SmallButton(label: String(localized: "Done")) { dismiss() } }
        }
        .padding(24).frame(width: 560)
    }

    private func add() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try? model.store.save(event: AppEvent(appId: allApps ? "" : model.appId ?? "", day: Day.string(date), title: name))
        title = ""
        model.revision += 1
    }
}
