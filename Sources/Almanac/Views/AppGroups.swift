import AlmanacCore
import SwiftUI

/// The app switcher's items: all apps together, saved groups, then each app.
struct AppMenuItems: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.apps.count > 1 {
            Button("All Apps") { model.appId = Store.allApps }
            ForEach(model.groups) { g in Button(g.name) { model.appId = g.id } }
            Divider()
        }
        ForEach(model.apps) { app in Button(app.name) { model.appId = app.id } }
        if model.apps.count > 1 {
            Divider()
            Button("Edit Groups…") { model.groupsOpen = true }
        }
    }
}

/// Named sets of apps (paid + lite, one app sold in several stores) whose numbers are added up.
struct GroupsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [Store.AppGroup] = []
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Groups").font(t.font(20, .bold))
            Text("A group adds up the numbers of its apps, like one app. Pick it in the app menu.").font(t.font(13)).foregroundStyle(t.label2)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    List(selection: $selected) {
                        ForEach(groups.indices, id: \.self) { i in Text(groups[i].name.isEmpty ? String(localized: "Untitled") : groups[i].name).tag(i) }
                    }
                    .frame(width: 180, height: 260)
                    HStack {
                        SmallButton(label: String(localized: "New Group"), symbol: "plus") {
                            groups.append(.init(name: String(localized: "Group \(groups.count + 1)"), ids: [])); selected = groups.count - 1
                        }
                        if let i = selected, i < groups.count {
                            SmallButton(label: String(localized: "Delete")) { groups.remove(at: i); selected = nil }
                        }
                    }
                }
                if let i = selected, i < groups.count {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "Name"), text: $groups[i].name).textFieldStyle(.roundedBorder)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.apps) { app in
                                    Toggle(app.name, isOn: Binding(get: { groups[i].ids.contains(app.id) }, set: { on in
                                        groups[i].ids.removeAll { $0 == app.id }
                                        if on { groups[i].ids.append(app.id) }
                                    }))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 226)
                    }
                } else {
                    Text("Select or create a group.").foregroundStyle(t.label3).frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            HStack {
                Spacer()
                SmallButton(label: String(localized: "Cancel")) { dismiss() }
                SmallButton(label: String(localized: "Save"), prominent: true) { save() }
            }
        }
        .padding(24).frame(width: 560)
        .onAppear { groups = model.store.groups() }
    }

    private func save() {
        // Names are the ids ("group:<name>"): drop empty groups and keep the first of two with the same name.
        var seen = Set<String>()
        let clean = groups.map { Store.AppGroup(name: $0.name.trimmingCharacters(in: .whitespaces), ids: $0.ids) }
            .filter { !$0.name.isEmpty && !$0.ids.isEmpty && seen.insert($0.name).inserted }
        model.store.setGroups(clean)
        if model.isAggregate, model.store.appIds(model.appId ?? "").isEmpty { model.appId = model.apps.first?.id }
        model.reload()
        dismiss()
    }
}
