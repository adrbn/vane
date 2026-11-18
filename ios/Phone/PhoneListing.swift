import AlmanacCore
import SwiftUI

/// Listing: locale picker, keyword warning with its fix, the five fields with their character budgets.
struct PhoneListing: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var locale = ""
    @State private var draft: ListingLocale?
    @State private var busy = false
    @State private var status: (text: String, error: Bool)?

    var body: some View {
        let _ = model.revision
        let locales = model.store.listing(model.appId ?? "")
        let saved = locales.first { $0.locale == locale } ?? locales.first
        PhoneScreen(title: String(localized: "Listing"), subtitle: String(localized: "What people see on the App Store")) {
            if !locales.isEmpty {
                Menu {
                    Picker("Language", selection: $locale) { ForEach(locales) { Text(name($0.locale)).tag($0.locale) } }
                } label: { pill(saved.map { name($0.locale) } ?? "") }
            }
        } content: {
            if let saved, let l = Binding($draft) {
                let repeated = ListingCheck.repeated(l.wrappedValue)
                if !repeated.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Keywords repeat the name or subtitle", systemImage: "exclamationmark.triangle.fill")
                            .font(t.font(15, .bold)).foregroundStyle(t.warn)
                        (repeated.count == 1
                            ? Text("“\(repeated.joined(separator: "”, “"))” already counts from the name or subtitle. The space is better used for new words.")
                            : Text("“\(repeated.joined(separator: "”, “"))” already count from the name or subtitle. The space is better used for new words."))
                            .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                        SmallButton(label: repeated.count == 1 ? String(localized: "Remove it") : String(localized: "Remove them"), prominent: true) {
                            l.wrappedValue.keywords = ListingCheck.removing(repeated, from: l.wrappedValue.keywords)
                        }
                    }
                    .phoneCard()
                }
                field(String(localized: "Name"), l.name, ListingView.limits.name)
                field(String(localized: "Subtitle"), l.subtitle, ListingView.limits.subtitle)
                field(String(localized: "Keywords"), l.keywords, ListingView.limits.keywords)
                ranks(l.wrappedValue)
                field(String(localized: "Promotional text"), l.promoText, ListingView.limits.promo, lines: 4)
                field(String(localized: "Description"), l.description, ListingView.limits.description, lines: 10)
                if let status { Text(status.text).font(t.font(12)).foregroundStyle(status.error ? t.neg : t.label2) }
                if l.wrappedValue != saved {
                    PhoneButton(label: busy ? String(localized: "Saving…") : model.isDemo ? String(localized: "Save") : String(localized: "Upload Changes")) { Task { await save(saved, l.wrappedValue) } }
                        .disabled(busy || ListingCheck(l.wrappedValue).overBudget)
                    PhoneButton(label: String(localized: "Discard"), prominent: false) { draft = saved }
                }
            } else {
                Text("No listing yet. It arrives with the first sync.").font(t.font(13)).foregroundStyle(t.label2).phoneCard()
            }
        }
        .onAppear { sync(locales) }
        .onChange(of: locale) { draft = locales.first { $0.locale == locale } }
        .onChange(of: model.appId) { locale = ""; sync(model.store.listing(model.appId ?? "")) }
    }

    private func sync(_ locales: [ListingLocale]) {
        if locale.isEmpty { locale = locales.first?.locale ?? "" }
        if draft?.locale != locale || draft?.appId != model.appId { draft = locales.first { $0.locale == locale } }
    }

    private func name(_ code: String) -> String {
        let l = Locale(identifier: code), en = Locale.current
        let lang = l.language.languageCode.flatMap { en.localizedString(forLanguageCode: $0.identifier) } ?? code
        return l.region.map { "\(lang) (\($0.identifier))" } ?? lang
    }

    private func pill(_ s: String) -> some View {
        HStack(spacing: 6) {
            Text(s).font(t.font(14, .semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label2)
        }
        .foregroundStyle(t.label)
        .padding(.horizontal, 14).frame(height: 38)
        .background(t.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(t.glassBorder, lineWidth: 1))
    }

    private func field(_ label: String, _ text: Binding<String>, _ limit: Int, lines: Int = 1) -> some View {
        let over = text.wrappedValue.count > limit
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(t.font(13, .semibold)).foregroundStyle(t.label2)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)").font(t.font(12, .semibold)).monospacedDigit()
                    .foregroundStyle(over ? t.neg : t.label3)
            }
            TextField("", text: text, axis: .vertical)
                .font(t.font(15)).lineLimit(lines == 1 ? 1...3 : lines...max(lines, 30))
        }
        .phoneCard(padding: 14)
    }

    /// Each keyword's best search position across the checked countries; long-press a chip for each country.
    @ViewBuilder private func ranks(_ l: ListingLocale) -> some View {
        let all = Dictionary(grouping: model.store.ranks(l.appId), by: \.term)
        let words = KeywordRanks.terms(l.keywords).filter { all[$0] != nil }
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Search position").font(t.font(13, .semibold)).foregroundStyle(t.label2)
                FlowLayout(spacing: 6) {
                    ForEach(words, id: \.self) { w in
                        let r = all[w] ?? []
                        HStack(spacing: 4) {
                            Text(w)
                            if let best = ListingView.best(r) { ListingView.rankLabel(best, t) }
                        }
                        .font(t.font(13)).lineLimit(1)
                        .padding(.horizontal, 9).frame(height: 26)
                        .background(t.fill, in: Capsule())
                        .contextMenu {
                            ForEach(r, id: \.self) { k in
                                Text("\(Territories.name(k.country.uppercased())): \(ListingView.position(k.rank))" + (k.previous.map { String(localized: " (was \(ListingView.position($0)))") } ?? ""))
                            }
                        }
                    }
                }
                if let day = all.values.first?.first?.day {
                    Text("Search position, best of \(Set(all.values.joined().map { $0.country.uppercased() }).sorted().joined(separator: ", ")) · \(AppStoreData.md(day))")
                        .font(t.font(11)).foregroundStyle(t.label3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .phoneCard(padding: 14)
        }
    }

    private func save(_ old: ListingLocale, _ new: ListingLocale) async {
        busy = true; defer { busy = false }
        do {
            if let s = model.syncer { try await s.updateListing(from: old, to: new) } else { try model.store.upsert(listing: new) }
            model.revision += 1
            status = (String(localized: "Saved."), false)
        } catch { status = (error.localizedDescription, true) }
    }
}
