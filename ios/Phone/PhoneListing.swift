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
        PhoneScreen(title: "Listing", subtitle: "What people see on the App Store") {
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
                        Text("“\(repeated.joined(separator: "”, “"))” already \(repeated.count == 1 ? "counts" : "count") from the name or subtitle. The space is better used for new words.")
                            .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                        SmallButton(label: "Remove \(repeated.count == 1 ? "it" : "them")", prominent: true) {
                            l.wrappedValue.keywords = ListingCheck.removing(repeated, from: l.wrappedValue.keywords)
                        }
                    }
                    .phoneCard()
                }
                field("Name", l.name, ListingView.limits.name)
                field("Subtitle", l.subtitle, ListingView.limits.subtitle)
                field("Keywords", l.keywords, ListingView.limits.keywords)
                field("Promotional text", l.promoText, ListingView.limits.promo, lines: 4)
                field("Description", l.description, ListingView.limits.description, lines: 10)
                if let status { Text(status.text).font(t.font(12)).foregroundStyle(status.error ? t.neg : t.label2) }
                if l.wrappedValue != saved {
                    PhoneButton(label: busy ? "Saving…" : model.isDemo ? "Save" : "Upload Changes") { Task { await save(saved, l.wrappedValue) } }
                        .disabled(busy || ListingCheck(l.wrappedValue).overBudget)
                    PhoneButton(label: "Discard", prominent: false) { draft = saved }
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
        let l = Locale(identifier: code), en = Locale(identifier: "en")
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

    private func save(_ old: ListingLocale, _ new: ListingLocale) async {
        busy = true; defer { busy = false }
        do {
            if let s = model.syncer { try await s.updateListing(from: old, to: new) } else { try model.store.upsert(listing: new) }
            model.revision += 1
            status = ("Saved.", false)
        } catch { status = (error.localizedDescription, true) }
    }
}
