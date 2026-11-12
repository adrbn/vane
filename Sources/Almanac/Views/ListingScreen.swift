#if os(macOS)
import AlmanacCore
import SwiftUI

/// Listing editor: localizations on the left, fields with Apple's character budgets on the right,
/// repeated-keyword detection, upload of only what changed.
struct ListingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    // The detail view is re-identified on every store revision (MacShell), so what must survive an upload lives in scene storage.
    @SceneStorage("listing.locale") private var locale = ""
    @State private var drafts: [String: ListingLocale] = [:]
    @AppStorage("listing.compare") private var compare = false
    @State private var busy = false
    @SceneStorage("listing.message") private var messageText = ""
    @SceneStorage("listing.messageIsError") private var messageIsError = false
    private var message: (text: String, error: Bool)? {
        get { messageText.isEmpty ? nil : (messageText, messageIsError) }
        nonmutating set { messageText = newValue?.text ?? ""; messageIsError = newValue?.error ?? false }
    }

    static let limits = (name: 30, subtitle: 30, keywords: 100, promo: 170, description: 4000)

    var body: some View {
        let live = model.store.listing(model.appId ?? "").sorted { ($0.locale == "en-US" ? "" : $0.locale) < ($1.locale == "en-US" ? "" : $1.locale) }
        let changed = live.filter { l in drafts[l.locale].map { $0 != l } ?? false }
        let selected = live.first { $0.locale == locale } ?? live.first
        Screen(title: "Listing", subtitle: "\(model.app?.name ?? "") · \(live.count) language\(live.count == 1 ? "" : "s")", inspector: true, scrolls: false) {
            GlassGroup {
                GlassItem(label: "Compare with Live", symbol: compare ? "checkmark" : nil) { compare.toggle() }
                GlassItem(label: "Discard Changes") { drafts = [:]; message = nil }
                    .disabled(changed.isEmpty).opacity(changed.isEmpty ? 0.45 : 1)
            }
            SmallButton(label: busy ? "Uploading…" : model.isDemo ? "Upload (demo)" : "Upload to App Store Connect", prominent: true) {
                Task { await upload(changed) }
            }
            .disabled(busy || changed.isEmpty || changed.contains { ListingCheck(drafts[$0.locale]!).overBudget })
            .opacity(busy || changed.isEmpty ? 0.5 : 1)
        } content: {
            if let l = selected {
                HStack(alignment: .top, spacing: 24) {
                    localizations(live, selected: l.locale)
                    editor(live: l)
                }
                .onAppear { if locale != l.locale { locale = l.locale } }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No listing yet").font(t.font(15, .bold))
                    Text("Your App Store listing is imported with the next refresh.").font(t.font(13)).foregroundStyle(t.label2)
                }
                .themedCard(padding: 24)
            }
        }
        .onAppear {
            model.chatContext = "Screen: App Store listing for \(model.app?.name ?? "")\n" + live.map {
                "[\($0.locale)] Name: \($0.name) | Subtitle: \($0.subtitle) | Keywords (\($0.keywords.count)/100): \($0.keywords) | Promo: \($0.promoText)\nDescription: \($0.description.prefix(800))"
            }.joined(separator: "\n\n")
        }
    }

    // MARK: Localizations

    private func localizations(_ live: [ListingLocale], selected: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Localizations").font(t.font(13, .semibold))
            VStack(spacing: 2) {
                ForEach(live) { l in
                    let d = drafts[l.locale] ?? l
                    let check = ListingCheck(d)
                    let sel = l.locale == selected
                    Button { locale = l.locale; message = nil } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.languageName(l.locale)).font(t.font(13, .semibold)).foregroundStyle(t.label).lineLimit(1)
                            Text(d != l ? "Edited" + (check.issues.isEmpty ? "" : " · \(check.issues[0])") : check.issues.first ?? "Ready")
                                .font(t.font(11)).lineLimit(1)
                                .foregroundStyle(check.issues.isEmpty ? (d != l ? t.accentText : t.label2) : t.warn)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sel ? t.accentSoft : .clear, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .themedCard(padding: 0)
            if let m = message {
                Text(m.text).font(t.font(11)).foregroundStyle(m.error ? t.neg : t.label2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 208)
    }

    static func languageName(_ code: String) -> String { Locale(identifier: "en").localizedString(forIdentifier: code) ?? code }

    // MARK: Editor

    private func binding(_ l: ListingLocale, _ kp: WritableKeyPath<ListingLocale, String>) -> Binding<String> {
        Binding(get: { (drafts[l.locale] ?? l)[keyPath: kp] },
                set: { var d = drafts[l.locale] ?? l; d[keyPath: kp] = $0; drafts[l.locale] = d; message = nil })
    }

    private func editor(live l: ListingLocale) -> some View {
        let d = drafts[l.locale] ?? l
        let repeats = ListingCheck.repeated(d)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                field("Name", nil, binding(l, \.name), live: l.name, limit: Self.limits.name)
                field("Subtitle", nil, binding(l, \.subtitle), live: l.subtitle, limit: Self.limits.subtitle)
            }
            VStack(alignment: .leading, spacing: 10) {
                field("Keywords", "Comma-separated, no spaces needed", binding(l, \.keywords), live: l.keywords, limit: Self.limits.keywords)
                if !repeats.isEmpty {
                    let chars = repeats.map(\.count).reduce(0, +) + repeats.count
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(t.warn)
                        Text("\(repeats.map { "“\($0)”" }.joined(separator: " and ")) \(repeats.count == 1 ? "is" : "are") already in your name or subtitle. Apple indexes those, so these \(chars) characters add nothing.")
                            .font(t.font(12)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        SmallButton(label: "Remove Repeated Words", prominent: true) {
                            binding(l, \.keywords).wrappedValue = ListingCheck.removing(repeats, from: d.keywords)
                        }
                    }
                    .padding(12)
                    .background(t.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
                }
            }
            field("Promotional text", "Can change without a new version", binding(l, \.promoText), live: l.promoText, limit: Self.limits.promo, lines: 2)
            field("Description", nil, binding(l, \.description), live: l.description, limit: Self.limits.description, fill: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func field(_ label: String, _ caption: String?, _ text: Binding<String>, live: String, limit: Int, lines: Int = 1, fill: Bool = false) -> some View {
        let n = text.wrappedValue.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label).font(t.font(13, .semibold))
                if let caption { Text(caption).font(t.font(11)).foregroundStyle(t.label2) }
                Spacer()
                Text("\(Num.int(Double(n))) / \(Num.int(Double(limit)))").font(t.font(11)).monospacedDigit()
                    .foregroundStyle(n > limit ? t.neg : t.label2)
            }
            Group {
                if lines == 1 && !fill {
                    TextField("", text: text).textFieldStyle(.plain).padding(.horizontal, 10).frame(height: 32)
                } else {
                    TextEditor(text: text).scrollContentBackground(.hidden).padding(.horizontal, 5).padding(.vertical, 8)
                        .frame(minHeight: fill ? 160 : 60, maxHeight: fill ? .infinity : 60)
                }
            }
            .font(t.font(13))
            .background(t.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(n > limit ? t.neg : t.sep2, lineWidth: 1))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.fill)
                    Capsule().fill(n > limit ? t.neg : t.accent).frame(width: g.size.width * min(1, Double(n) / Double(limit)))
                }
            }
            .frame(height: 2)
            if compare && text.wrappedValue != live {
                Text("Live: " + (live.isEmpty ? "empty" : live)).font(t.font(11)).foregroundStyle(t.label2).lineLimit(2).textSelection(.enabled)
            }
        }
        .frame(maxHeight: fill ? .infinity : nil, alignment: .top)
    }

    // MARK: Upload

    private func upload(_ changed: [ListingLocale]) async {
        busy = true; defer { busy = false }
        var done = 0
        for old in changed {
            guard let new = drafts[old.locale] else { continue }
            do {
                if let s = model.syncer { try await s.updateListing(from: old, to: new) } else { try model.store.upsert(listing: new) }
                drafts[old.locale] = nil
                done += 1
            } catch {
                message = ("\(Self.languageName(old.locale)): \(error.localizedDescription)", true)
                model.revision += 1
                return
            }
        }
        _ = model.runEngine()
        model.revision += 1
        message = ("Uploaded \(done) language\(done == 1 ? "" : "s")\(model.isDemo ? " (demo, nothing left this Mac)" : "").", false)
    }
}

/// Budget and keyword checks for one localization.
struct ListingCheck {
    let l: ListingLocale
    init(_ l: ListingLocale) { self.l = l }

    var overBudget: Bool {
        let m = ListingView.limits
        return l.name.count > m.name || l.subtitle.count > m.subtitle || l.keywords.count > m.keywords
            || l.promoText.count > m.promo || l.description.count > m.description
    }

    var issues: [String] {
        var out: [String] = []
        if overBudget { out.append("Over the character limit") }
        let r = Self.repeated(l).count
        if r > 0 { out.append("\(r) repeated keyword\(r == 1 ? "" : "s")") }
        if l.subtitle.isEmpty { out.append("Subtitle missing") }
        if l.promoText.isEmpty { out.append("Promotional text missing") }
        return out
    }

    private static func words(_ s: String) -> [String] { s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }

    /// Keyword entries whose words all already appear in the name or subtitle.
    static func repeated(_ l: ListingLocale) -> [String] {
        let shown = Set(words(l.name + " " + l.subtitle))
        return l.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && words($0).allSatisfy(shown.contains) }
    }

    static func removing(_ entries: [String], from keywords: String) -> String {
        let drop = Set(entries.map { $0.lowercased() })
        return keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !drop.contains($0.lowercased()) }.joined(separator: ",")
    }
}
#endif
