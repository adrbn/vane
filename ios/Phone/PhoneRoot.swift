import AlmanacCore
import SwiftUI

enum PhoneTab: Hashable { case today, appStore, reviews, listing, ask }

/// iPhone root: welcome until a key (or the demo) is chosen, then the four tabs plus Ask.
/// Ask uses the search role so iOS draws it as the separate circle next to the glass tab bar.
struct PhoneRoot: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.blocks.id
    @State private var tab: PhoneTab = .today

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        Group {
            if model.onboardingOpen {
                WelcomeFlow()
            } else {
                TabView(selection: $tab) {
                    Tab("Today", systemImage: "calendar", value: PhoneTab.today) { NavigationStack { TodayScreen(tab: $tab) } }
                    Tab("App Store", systemImage: "chart.bar.fill", value: PhoneTab.appStore) { NavigationStack { AppStoreTab() } }
                    Tab("Reviews", systemImage: "text.bubble", value: PhoneTab.reviews) { NavigationStack { PhoneReviews() } }
                    Tab("Listing", systemImage: "doc.text", value: PhoneTab.listing) { NavigationStack { PhoneListing() } }
                    Tab("Ask", systemImage: "sparkles", value: PhoneTab.ask, role: .search) { NavigationStack { AskScreen() } }
                }
                .tint(t.accentText)
            }
        }
        .environment(\.theme, t)
        .task(id: "\(model.revision) \(model.appId ?? "") \(themeId)") { WidgetFeed.write(model, theme: t) }
        .preferredColorScheme(t.scheme)
        .fontDesign(t.design)
    }
}
