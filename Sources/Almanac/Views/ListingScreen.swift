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
        Screen(title: String(localized: "Listing"), subtitle: String(localized: "\(model.app?.name ?? "") · \(live.count) languages"), inspector: true, scrolls: false) {
            GlassGroup {
                GlassItem(label: String(localized: "Compare with Live"), symbol: compare ? "checkmark" : nil) { compare.toggle() }
                GlassItem(label: String(localized: "Discard Changes")) { drafts = [:]; message = nil }
                    .disabled(changed.isEmpty).opacity(changed.isEmpty ? 0.45 : 1)
            }
            SmallButton(label: busy ? String(localized: "Uploading…") : model.isDemo ? String(localized: "Upload (demo)") : String(localized: "Upload to App Store Connect"), prominent: true, busy: busy) {
                Task { await upload(changed) }
            }
            .disabled(!busy && (changed.isEmpty || changed.contains { ListingCheck(drafts[$0.locale]!).overBudget }))
            .opacity(!busy && changed.isEmpty ? 0.5 : 1)
        } content: {
            if let l = selected {
                HStack(alignment: .top, spacing: 24) {
                    localizations(live, selected: l.locale)
                    editor(live: l)
                }
                .onAppear { if locale != l.locale { locale = l.locale } }
                .onChange(of: model.pendingLink, initial: true) {
                    guard let link = model.pendingLink else { return }
                    model.pendingLink = nil
                    if let want = link.locale, live.contains(where: { $0.locale == want }) { locale = want }
                }
            } else if model.isAggregate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick one app to edit its listing").font(t.font(15, .bold))
                    Text("Each app has its own App Store page. Numbers, reviews and insights can be seen together; the listing can't.").font(t.font(13)).foregroundStyle(t.label2)
                }
                .themedCard(padding: 24)
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
        // An issue every language shares is said once under the list, not repeated on each row.
        let sets = live.map { Set(ListingCheck(drafts[$0.locale] ?? $0).issues) }
        let shared = sets.dropFirst().reduce(sets.first ?? []) { $0.intersection($1) }
        let sel = live.first { $0.locale == selected }.map { drafts[$0.locale] ?? $0 }
        let list = VStack(spacing: 2) {
                ForEach(live) { l in
                    let d = drafts[l.locale] ?? l
                    let own = ListingCheck(d).issues.filter { !shared.contains($0) || live.count == 1 }
                    let on = l.locale == selected
                    Button { locale = l.locale; message = nil } label: {
                        HStack(spacing: 8) {
                            Text(Self.languageName(l.locale)).font(t.font(13, .semibold)).foregroundStyle(t.label).lineLimit(1)
                            Spacer(minLength: 4)
                            if d != l {
                                Text("Edited").font(t.font(11, .semibold)).foregroundStyle(t.accentText)
                            } else if let issue = own.first {
                                Circle().fill(t.warn).frame(width: 6, height: 6).help(own.joined(separator: "\n"))
                                    .accessibilityLabel(issue)
                            } else {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(t.label3)
                            }
                        }
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(on ? t.accentSoft : .clear, in: RoundedRectangle(cornerRadius: t.inner(6, in: t.rS), style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Localizations").font(t.font(13, .semibold))
            // Many languages would make the column taller than the window, which pushes the whole screen under the title bar.
            ViewThatFits(in: .vertical) { list; ScrollView { list }.scrollIndicators(.automatic) }
                .themedCard(padding: 0, radius: t.rS) // same corner as the fields beside it
            if live.count > 1, let issue = shared.sorted().first {
                Label("\(issue) in every language", systemImage: "exclamationmark.circle")
                    .font(t.font(11)).foregroundStyle(t.warn).padding(.horizontal, 4)
            }
            if let m = message {
                Text(m.text).font(t.font(11)).foregroundStyle(m.error ? t.neg : t.label2).fixedSize(horizontal: false, vertical: true)
            }
            if let sel { preview(sel) }
        }
        .frame(width: 240)
    }

    static func previewPad(_ t: AlmanacTheme) -> CGFloat { min(max(t.r - 10, 10), 18) }

    /// How the name and subtitle read in App Store search, plus the keywords as Apple indexes them.
    private func preview(_ l: ListingLocale) -> some View {
        let words = l.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let repeats = Set(ListingCheck.repeated(l))
        return VStack(alignment: .leading, spacing: 12) {
            Text("In search").font(t.font(11, .semibold)).foregroundStyle(t.label2)
            // App Store layout: Get on the right. Name and subtitle take two lines at most and shrink a little
            // rather than end in "…" (30 characters each fit at 75 %).
            HStack(spacing: 10) {
                if let app = model.app { AppIconView(app: app, size: 44) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.name.isEmpty ? String(localized: "No name") : l.name).font(t.font(13, .semibold))
                        .lineLimit(2).minimumScaleFactor(0.75)
                    Text(l.subtitle.isEmpty ? String(localized: "No subtitle") : l.subtitle).font(t.font(11)).foregroundStyle(t.label2)
                        .lineLimit(2).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                getButton
            }
            if !words.isEmpty {
                Text("Keywords · \(words.count)").font(t.font(11, .semibold)).foregroundStyle(t.label2).padding(.top, 4)
                FlowLayout(spacing: 4) {
                    ForEach(words, id: \.self) { w in
                        Text(w).font(t.font(11)).lineLimit(1)
                            .foregroundStyle(repeats.contains(w) ? t.warn : t.label)
                            .padding(.horizontal, 7).frame(height: 20)
                            .background(repeats.contains(w) ? t.warn.opacity(0.14) : t.fill, in: Capsule())
                    }
                }
            }
            // What shows under the screenshots: the promotional text, else the start of the description.
            Text(l.promoText.isEmpty ? String(localized: "Product page · description") : String(localized: "Product page · promotional text")).font(t.font(11, .semibold)).foregroundStyle(t.label2).padding(.top, 4)
            // The text lays out at full height in an overlay, which doesn't size the card: the fade cuts it, not a "…".
            Color.clear.frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    Text(l.promoText.isEmpty ? l.description : l.promoText).font(t.font(12)).foregroundStyle(t.label2).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .themedCard(padding: Self.previewPad(t), radius: t.rS) // same corner as the fields beside it
    }

    /// Opens the app's public App Store page. Demo apps have made-up IDs, so there it's only a label.
    @ViewBuilder private var getButton: some View {
        let label = Text("Get").font(t.font(12, .bold)).foregroundStyle(t.accentText)
            .padding(.horizontal, 12).frame(height: 24).background(t.fill, in: Capsule())
        if let app = model.app, !model.isDemo, let url = URL(string: "https://apps.apple.com/app/id\(app.id)") {
            Link(destination: url) { label }.buttonStyle(.plain).help("Open on the App Store")
        } else {
            label
        }
    }

    static func languageName(_ code: String) -> String { Locale.current.localizedString(forIdentifier: code) ?? code }

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
                field(String(localized: "Name"), nil, binding(l, \.name), live: l.name, limit: Self.limits.name)
                field(String(localized: "Subtitle"), nil, binding(l, \.subtitle), live: l.subtitle, limit: Self.limits.subtitle)
            }
            VStack(alignment: .leading, spacing: 10) {
                field(String(localized: "Keywords"), String(localized: "Comma-separated, no spaces needed"), binding(l, \.keywords), live: l.keywords, limit: Self.limits.keywords)
                if !repeats.isEmpty {
                    let chars = repeats.map(\.count).reduce(0, +) + repeats.count
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(t.warn)
                        Text(repeats.count == 1 ? String(localized: "\(repeats.map { "“\($0)”" }.formatted(.list(type: .and))) is already in your name or subtitle. Apple indexes those, so these \(chars) characters add nothing.") : String(localized: "\(repeats.map { "“\($0)”" }.formatted(.list(type: .and))) are already in your name or subtitle. Apple indexes those, so these \(chars) characters add nothing."))
                            .font(t.font(12)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        SmallButton(label: String(localized: "Remove Repeated Words"), prominent: true) {
                            binding(l, \.keywords).wrappedValue = ListingCheck.removing(repeats, from: d.keywords)
                        }
                    }
                    .padding(12)
                    .background(t.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
                }
            }
            field(String(localized: "Promotional text"), String(localized: "Can change without a new version"), binding(l, \.promoText), live: l.promoText, limit: Self.limits.promo, lines: 2)
            field(String(localized: "Description"), nil, binding(l, \.description), live: l.description, limit: Self.limits.description, fill: true)
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
                    .foregroundStyle(n > limit ? t.neg : n > limit * 9 / 10 ? t.warn : t.label3)
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
            .background(t.field, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.rS, style: .continuous).strokeBorder(n > limit ? t.neg : t.sep, lineWidth: 1))
            if compare && text.wrappedValue != live {
                Text(String(localized: "Live: \(live.isEmpty ? String(localized: "empty") : live)")).font(t.font(11)).foregroundStyle(t.label2).lineLimit(2).textSelection(.enabled)
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
        message = (model.isDemo ? String(localized: "Uploaded \(done) languages (demo, nothing left this Mac).") : String(localized: "Uploaded \(done) languages."), false)
    }
}

/// Wraps its children onto as many lines as the width needs.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in rows(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func rows(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing; line = max(line, s.height); widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + line))
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
        if overBudget { out.append(String(localized: "Over the character limit")) }
        let r = Self.repeated(l).count
        if r > 0 { out.append(String(localized: "\(r) repeated keywords")) }
        if l.subtitle.isEmpty { out.append(String(localized: "Subtitle missing")) }
        if l.promoText.isEmpty { out.append(String(localized: "Promotional text missing")) }
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
