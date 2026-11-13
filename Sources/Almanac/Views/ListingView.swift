import AlmanacCore
import SwiftUI

/// Read-and-check view of the store listing per locale, with the character budgets
/// Apple enforces and repeated-word warnings.
struct LegacyListingView: View {
    @Environment(AppModel.self) private var model
    @State private var locale = ""
    @State private var keywords = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        let all = model.store.listing(model.appId ?? "")
        let current = all.first { $0.locale == locale } ?? all.first
        ScrollView {
            if let l = current {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Picker("Locale", selection: $locale) {
                            ForEach(all) { Text(Locale.current.localizedString(forIdentifier: $0.locale) ?? $0.locale).tag($0.locale) }
                        }
                        .labelsHidden().fixedSize()
                        Spacer()
                        Button("Review with AI") {
                            model.ask("Review my App Store listing for \(Locale(identifier: "en").localizedString(forIdentifier: l.locale) ?? l.locale). What would you change in name, subtitle and keywords to rank for more searches? Be specific.")
                        }
                    }
                    field(String(localized: "Name"), l.name, limit: 30)
                    field(String(localized: "Subtitle"), l.subtitle, limit: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        budgetHeader(String(localized: "Keywords"), count: keywords.count, limit: 100)
                        TextField("keyword,keyword", text: $keywords, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                        let repeats = repeated(l, keywords)
                        if !repeats.isEmpty {
                            Label("Already in name or subtitle: \(repeats.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button(model.isDemo ? String(localized: "Save (demo)") : String(localized: "Save to App Store Connect")) { Task { await save(l) } }
                                .disabled(busy || keywords == l.keywords || keywords.count > 100)
                        }
                    }
                    .card()
                    field(String(localized: "Promotional text"), l.promoText, limit: 170)
                    field(String(localized: "Description"), l.description, limit: 4000)
                }
                .padding(20)
                .onAppear { if locale.isEmpty || keywords.isEmpty { locale = l.locale; keywords = l.keywords } }
                .onChange(of: locale) { keywords = all.first { $0.locale == locale }?.keywords ?? "" ; message = nil }
            } else {
                EmptyHint(title: String(localized: "No listing yet"), message: String(localized: "Refresh to import your App Store listing."), symbol: "text.page").padding(.top, 60)
            }
        }
        .onAppear {
            model.chatContext = "Screen: App Store listing for \(model.app?.name ?? "")\n" + all.map {
                "[\($0.locale)] Name: \($0.name) | Subtitle: \($0.subtitle) | Keywords (\($0.keywords.count)/100): \($0.keywords) | Promo: \($0.promoText)\nDescription: \($0.description.prefix(800))"
            }.joined(separator: "\n\n")
        }
    }

    private func budgetHeader(_ title: String, count: Int, limit: Int) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(count) / \(limit)").font(.caption).monospacedDigit().foregroundStyle(count > limit ? .red : count < limit * 8 / 10 && limit <= 100 ? .orange : .secondary)
        }
    }

    private func field(_ title: String, _ value: String, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            budgetHeader(title, count: value.count, limit: limit)
            Text(value.isEmpty ? String(localized: "Empty") : value).foregroundStyle(value.isEmpty ? .tertiary : .primary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }

    private func repeated(_ l: ListingLocale, _ kw: String) -> [String] {
        let words = { (s: String) in s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let shown = Set(words(l.name + " " + l.subtitle))
        return kw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && words($0).allSatisfy(shown.contains) }
    }

    private func save(_ l: ListingLocale) async {
        busy = true; defer { busy = false }
        do {
            if let s = model.syncer { try await s.updateKeywords(l, keywords: keywords) }
            else { var c = l; c.keywords = keywords; try model.store.upsert(listing: c) }
            model.runEngine()
            message = String(localized: "Saved.")
        } catch { message = error.localizedDescription }
    }
}
