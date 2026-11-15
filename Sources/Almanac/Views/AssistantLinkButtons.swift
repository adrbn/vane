import AlmanacCore
import SwiftUI

/// The assistant's suggested destinations, one button each. Only `AppModel.follow` acts on them.
struct AssistantLinkButtons: View {
    @Environment(AppModel.self) private var model
    var links: [AssistantLink]
    var body: some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(links, id: \.self) { l in
                    SmallButton(label: label(l)) { model.follow(l) }
                }
            }
        }
    }

    private func label(_ l: AssistantLink) -> String {
        guard l.label.isEmpty else { return l.label }
        if case .pin(let m) = l.action { return String(localized: "Pin \(m.title)") }
        return String(localized: "Open")
    }
}
