import AlmanacCore
import NaturalLanguage
import Charts
import SwiftUI
import Translation

/// Reviews: summary column (ratings, latest version, waiting for a reply) + list with Translate / Reply….
struct ReviewsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var needsReply = false
    @State private var rating = 0
    @State private var territory: String?
    @State private var version: String?
    @State private var search = ""
    @State private var searching = false
    @State private var replying: Review?

    var body: some View {
        let app = model.appId ?? ""
        let all = model.store.reviews(app)
        let versions = model.store.versions(app)
        let shown = all.filter {
            (!needsReply || $0.response == nil) && (rating == 0 || $0.rating == rating)
                && (territory == nil || $0.territory == territory)
                && (version == nil || ReviewInfo.version($0, versions) == version)
                && (search.isEmpty || "\($0.title) \($0.body) \($0.reviewer)".localizedCaseInsensitiveContains(search))
        }
        ZStack {
            Screen(title: String(localized: "Reviews"), subtitle: "\(model.app?.name ?? "") · \(String(localized: "\(all.count) written reviews"))", inspector: true, scrolls: false) {
                controls(all, versions)
            } content: {
                // Two panes that always reach the bottom of the window, like Mail: a short list leaves room
                // inside its pane, never a hole under a floating card.
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        summary(all)
                        versionCard(all, versions)
                        waitingCard(all)
                        byVersion(all, versions)
                    }
                    .frame(width: 256)
                    list(shown, all: all, versions: versions)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .blur(radius: replying == nil ? 0 : 16)
            if let r = replying {
                CenteredSheet(onDismiss: { replying = nil }) {
                    ThemedReplySheet(review: r, version: ReviewInfo.version(r, versions), close: { replying = nil })
                }
            }
        }
        .onAppear {
            model.chatContext = "Screen: Reviews for \(model.app?.name ?? "")\n"
                + all.prefix(60).map { "[\($0.rating)★ \($0.created) \($0.territory)\($0.response == nil ? "" : ", replied")] \($0.title): \($0.body)" }.joined(separator: "\n")
        }
    }

    // MARK: Toolbar

    @ViewBuilder private func controls(_ all: [Review], _ versions: [VersionMark]) -> some View {
        GlassSegments(options: [(false, String(localized: "All")), (true, String(localized: "Needs reply"))], selection: $needsReply)
        GlassGroup {
            menu(rating == 0 ? String(localized: "All ratings") : String(localized: "\(rating) stars")) {
                Button("All ratings") { rating = 0 }
                Divider()
                ForEach((1...5).reversed(), id: \.self) { n in Button("\(n) stars") { rating = n } }
            }
            menu(territory.map(Territories.name) ?? String(localized: "All territories")) {
                Button("All territories") { territory = nil }
                Divider()
                ForEach(Array(Set(all.map(\.territory))).sorted { Territories.name($0) < Territories.name($1) }, id: \.self) { c in
                    Button(Territories.name(c)) { territory = c }
                }
            }
            menu(version.map { String(localized: "Version \($0)") } ?? String(localized: "All versions")) {
                Button("All versions") { version = nil }
                Divider()
                ForEach(versions.reversed(), id: \.self) { v in Button("Version \(v.version)") { version = v.version } }
            }
        }
        if searching {
            GlassGroup {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.label2).padding(.leading, 8)
                TextField("Search reviews", text: $search).textFieldStyle(.plain).font(t.font(13)).frame(width: 150)
                Button { search = ""; searching = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(t.label3).padding(.trailing, 6)
                }
                .buttonStyle(.plain)
            }
        } else {
            GlassIconButton(symbol: "magnifyingglass", help: String(localized: "Search reviews")) { searching = true }
        }
    }

    private func menu<C: View>(_ label: String, @ViewBuilder _ items: () -> C) -> some View {
        Menu { items() } label: {
            HStack(spacing: 6) {
                Text(label)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label2)
            }
            .font(t.font(13, .semibold)).padding(.horizontal, 10).frame(height: 28).contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Left column

    private func summary(_ all: [Review]) -> some View {
        let avg = ReviewInfo.average(all)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text.tracked(all.isEmpty ? "—" : String(format: "%.1f", avg), -1).font(t.font(48, .bold)).monospacedDigit()
                    .foregroundStyle(all.isEmpty ? t.label3 : t.label)
                VStack(alignment: .leading, spacing: 2) {
                    ThemedStars(rating: Int(avg.rounded()), size: 11)
                    Text("\(all.count) written reviews").font(t.font(11)).foregroundStyle(t.label2)
                }
            }
            VStack(spacing: 6) {
                ForEach((1...5).reversed(), id: \.self) { n in
                    let share = all.isEmpty ? 0 : Double(all.filter { $0.rating == n }.count) / Double(all.count)
                    HStack(spacing: 8) {
                        Text("\(n)").font(t.font(11)).foregroundStyle(t.label2).frame(width: 8)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(t.fill)
                                Capsule().fill(t.accent).frame(width: g.size.width * share)
                            }
                        }
                        .frame(height: 5)
                        Text(String(format: "%.0f%%", share * 100)).font(t.font(11)).foregroundStyle(t.label2).monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
        .themedCard(padding: 20)
    }

    private func versionCard(_ all: [Review], _ versions: [VersionMark]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let latest = versions.last {
                let now = all.filter { $0.created >= latest.day }
                let prev = versions.dropLast().last
                let before = prev.map { p in all.filter { $0.created >= p.day && $0.created < latest.day } } ?? []
                Text("Version \(latest.version) · since \(AppStoreData.md(latest.day))").font(t.font(11)).foregroundStyle(t.label2)
                if now.isEmpty {
                    Text("—").font(t.font(28, .bold)).foregroundStyle(t.label3)
                    Text("No reviews since this release yet").font(t.font(11)).foregroundStyle(t.label2)
                } else {
                    let a = ReviewInfo.average(now)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", a)).font(t.font(28, .bold)).monospacedDigit()
                        if let p = prev, !before.isEmpty {
                            let d = a - ReviewInfo.average(before)
                            (abs(d) < 0.05 ? Text("No change") : Text(String(format: "%@%.1f", d > 0 ? "+" : "−", abs(d))))
                                .font(t.font(13, .bold)).monospacedDigit().foregroundStyle(abs(d) < 0.05 ? t.label2 : d > 0 ? t.pos : t.neg)
                            Text("vs \(p.version)").font(t.font(13)).foregroundStyle(t.label2)
                        }
                    }
                    Text("\(now.count) written reviews").font(t.font(11)).foregroundStyle(t.label2)
                }
            } else {
                Text("Latest version").font(t.font(11)).foregroundStyle(t.label2)
                Text("No releases recorded yet").font(t.font(13)).foregroundStyle(t.label3)
            }
        }
        .themedCard(padding: 20)
    }

    private func waitingCard(_ all: [Review]) -> some View {
        let waiting = all.filter { $0.response == nil }
        let low = waiting.filter { $0.rating <= 2 }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("Waiting for a reply").font(t.font(11)).foregroundStyle(t.label2)
            Text("\(waiting.count)").font(t.font(28, .bold)).monospacedDigit()
            Text(waiting.isEmpty ? String(localized: "You're all caught up")
                 : String(localized: "Oldest from \(AppStoreData.md(waiting.map(\.created).min()!)) · \(low) are 1–2 stars"))
                .font(t.font(11)).foregroundStyle(t.label2)
        }
        .themedCard(padding: 20)
    }

    /// Every release with its written reviews: count and average, newest first. Fills the rest of the column.
    private func byVersion(_ all: [Review], _ versions: [VersionMark]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By version").font(t.font(11)).foregroundStyle(t.label2)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(versions.enumerated().reversed()), id: \.offset) { i, v in
                        let end = i + 1 < versions.count ? versions[i + 1].day : "9999"
                        let rs = all.filter { $0.created >= v.day && $0.created < end }
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.version).font(t.font(13, .semibold)).monospacedDigit()
                                Text(AppStoreData.md(v.day)).font(t.font(11)).foregroundStyle(t.label2)
                            }
                            Spacer(minLength: 4)
                            if rs.isEmpty {
                                Text("No reviews").font(t.font(11)).foregroundStyle(t.label3)
                            } else {
                                Text(String(format: "%.1f ★ · %d", ReviewInfo.average(rs), rs.count)).font(t.font(12, .semibold)).monospacedDigit()
                            }
                        }
                        .frame(height: 40)
                        .overlay(alignment: .top) { if i != versions.count - 1 { t.sep.frame(height: 1) } }
                    }
                    if versions.isEmpty { Text("No releases recorded yet").font(t.font(13)).foregroundStyle(t.label3) }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedCard(padding: 20)
    }

    // MARK: List

    @ViewBuilder private func list(_ shown: [Review], all: [Review], versions: [VersionMark]) -> some View {
        if shown.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(all.isEmpty ? String(localized: "No reviews yet") : search.isEmpty ? String(localized: "No reviews match these filters") : String(localized: "No reviews mention “\(search)”")).font(t.font(15, .bold))
                Text(all.isEmpty ? String(localized: "Written App Store reviews show up here after a refresh.") : search.isEmpty ? String(localized: "Try All ratings, All territories or All versions.") : String(localized: "Search looks at titles, review text and reviewer names."))
                    .font(t.font(13)).foregroundStyle(t.label2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedCard(padding: 24)
        } else {
            GeometryReader { g in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                            ThemedReviewRow(review: r, version: ReviewInfo.version(r, versions), replying: $replying)
                                .overlay(alignment: .top) { if i > 0 { t.sep.frame(height: 1) } }
                        }
                        // A short list leaves room: use it for the context of those reviews, from real data.
                        if shown.count <= 4 {
                            ReviewContext(reviews: all, versions: versions)
                                .frame(minHeight: 240, maxHeight: .infinity)
                                .overlay(alignment: .top) { t.sep.frame(height: 1) }
                        } else {
                            Spacer(minLength: 24)
                        }
                        Text(shown.count == all.count ? String(localized: "That's every written review. New ones arrive with each refresh.")
                             : String(localized: "\(shown.count) of \(all.count) written reviews match these filters."))
                            .font(t.font(12)).foregroundStyle(t.label3).padding(.bottom, 20)
                    }
                    .frame(minHeight: g.size.height)
                }
                .scrollIndicators(.never)
            }
            .themedCard(padding: 0)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Where the written reviews sit against downloads: a few counts, then weekly downloads with each review pinned on its week.
private struct ReviewContext: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let reviews: [Review]
    let versions: [VersionMark]

    var body: some View {
        let app = model.appId ?? ""
        let daily = model.store.series(app, .downloads)
        let weeks = Dictionary(grouping: daily) { Day.weekStart($0.day) }.map { (day: $0.key, value: $0.value.map(\.value).reduce(0, +)) }.sorted { $0.day < $1.day }
        let total = daily.map(\.value).reduce(0, +)
        let replied = reviews.filter { $0.response != nil }.count
        let last = reviews.map(\.created).max()
        let ratings = model.store.series(app, .ratingsTotal).last?.value
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Reviews against downloads").font(t.font(15, .bold))
                Text("Weekly downloads, each written review pinned on its week").font(t.font(12)).foregroundStyle(t.label2).lineLimit(1)
            }
            HStack(spacing: 0) {
                stat(reviews.isEmpty ? "—" : Num.int(total / Double(reviews.count)), String(localized: "downloads per written review"))
                    .opens { model.section = .metric(.downloads) }
                stat(String(localized: "\(replied) of \(reviews.count)"), String(localized: "answered"))
                stat(last.map { String(localized: "\(Day.between($0, Day.today())) days") } ?? "—", String(localized: "since the last review"))
                stat(ratings.map(Num.int) ?? "—", String(localized: "ratings on the App Store"))
                    .opens { model.section = .usage }
            }
            Chart {
                ForEach(weeks, id: \.day) { w in
                    BarMark(x: .value("Week", Day.date(w.day), unit: .weekOfYear), y: .value("Downloads", w.value))
                        .foregroundStyle(t.accent.opacity(0.35)).cornerRadius(3)
                }
                ForEach(versions.filter { $0.day >= (weeks.first?.day ?? "0") }) { v in
                    RuleMark(x: .value("Release", Day.date(v.day)))
                        .foregroundStyle(t.label3).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) { Text(v.version).font(t.font(10)).foregroundStyle(t.label2) }
                }
                ForEach(reviews) { r in
                    let w = Day.weekStart(r.created)
                    PointMark(x: .value("Week", Day.date(w), unit: .weekOfYear), y: .value("Downloads", weeks.first { $0.day == w }?.value ?? 0))
                        .symbol { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(t.accent) }
                        .annotation(position: .top) { Text("\(r.rating)★").font(t.font(10, .semibold)).foregroundStyle(t.label) }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing) { AxisGridLine().foregroundStyle(t.sep); AxisValueLabel().font(t.font(10)).foregroundStyle(t.label2) } }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale.current)).font(t.font(10)).foregroundStyle(t.label2) } }
            .frame(maxHeight: .infinity)
            .padding(.top, 14)
        }
        .padding(20)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(t.font(17, .bold)).monospacedDigit().lineLimit(1)
            Text(label).font(t.font(11)).foregroundStyle(t.label2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ReviewInfo {
    static func average(_ r: [Review]) -> Double { r.isEmpty ? 0 : Double(r.map(\.rating).reduce(0, +)) / Double(r.count) }
    /// The version that was live when the review was written (reviews carry no version of their own).
    static func version(_ r: Review, _ versions: [VersionMark]) -> String? { versions.last { $0.day <= r.created }?.version }
    /// Dominant language code of a text, nil when unsure.
    static func language(_ s: String) -> String? {
        let r = NLLanguageRecognizer(); r.processString(s)
        guard let (lang, p) = r.languageHypotheses(withMaximum: 1).first, p > 0.6 else { return nil }
        return lang.rawValue
    }
    static func languageName(_ code: String) -> String { Locale.current.localizedString(forLanguageCode: code) ?? code }
}

struct ThemedStars: View {
    @Environment(\.theme) private var t
    var rating: Int
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { Image(systemName: "star.fill").foregroundStyle($0 <= rating ? t.label : t.label3) }
        }
        .font(.system(size: size * 0.8))
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}

struct ThemedReviewRow: View {
    @Environment(\.theme) private var t
    var review: Review
    var version: String?
    @Binding var replying: Review?
    @State private var translation: String?
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        let foreign = ReviewInfo.language(review.title + ". " + review.body).map { $0 != "en" } ?? false
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ThemedStars(rating: review.rating)
                Text(review.title).font(t.font(13, .semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(AppStoreData.md(review.created)).font(t.font(11)).foregroundStyle(t.label2)
            }
            Text(translation ?? review.body).font(t.font(13)).lineSpacing(3).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 8) {
                Text(([review.reviewer, "\(Territories.flag(review.territory)) \(Territories.name(review.territory))"] + (version.map { [String(localized: "Version \($0)")] } ?? [])).joined(separator: " · "))
                    .font(t.font(11)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if foreign {
                    SmallButton(label: translation == nil ? String(localized: "Translate") : String(localized: "Show Original")) {
                        if translation != nil { translation = nil } else { config = .init(target: Locale.Language(identifier: "en")) }
                    }
                }
                if review.response == nil {
                    SmallButton(label: String(localized: "Reply…"), symbol: "sparkles", prominent: true) { replying = review }
                }
            }
            .padding(.top, 2)
            if let r = review.response {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your reply").font(t.font(11, .semibold)).foregroundStyle(t.label2)
                    Text(r).font(t.font(12)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(t.fill2, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: t.rS, style: .continuous).strokeBorder(t.sep, lineWidth: 1))
                .padding(.top, 4)
            }
        }
        .padding(16)
        .translationTask(config) { session in
            // Apple's on-device translator: the review never leaves the Mac.
            translation = try? await session.translate(review.body).targetText
            config = nil
        }
    }
}

/// Suggested reply, drafted in the reviewer's language; the developer edits and sends.
struct ThemedReplySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var review: Review
    var version: String?
    var close: () -> Void
    @State private var text = ""
    @State private var lastDraft = ""
    @State private var tone = "Friendly"
    @State private var busy = false
    @State private var error: String?
    @State private var translation: String?
    @State private var showOriginal = false
    @State private var config: TranslationSession.Configuration?
    @FocusState private var focused: Bool

    private var lang: String { ReviewInfo.language(review.title + ". " + review.body) ?? "en" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reply to \(review.reviewer)").font(t.font(20, .bold))
                Text(([String(localized: "\(review.rating) stars"), "“\(review.title)”", "\(Territories.flag(review.territory)) \(Territories.name(review.territory))"]
                      + (version.map { [String(localized: "Version \($0)")] } ?? []) + [AppStoreData.md(review.created)]).joined(separator: " · "))
                    .font(t.font(12)).foregroundStyle(t.label2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(showOriginal || translation == nil ? review.body : translation!).font(t.font(13)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if lang != "en", translation == nil {
                    HStack(spacing: 4) {
                        Text("Written in \(ReviewInfo.languageName(lang))").foregroundStyle(t.label2)
                        Text("·").foregroundStyle(t.label2)
                        Button("Translate") { config = .init(target: Locale.Language(identifier: "en")) }
                            .buttonStyle(.plain).foregroundStyle(t.accentText)
                    }
                    .font(t.font(11))
                }
                if lang != "en", translation != nil {
                    HStack(spacing: 4) {
                        (showOriginal ? Text("Original in \(ReviewInfo.languageName(lang))") : Text("Translated from \(ReviewInfo.languageName(lang))")).foregroundStyle(t.label2)
                        Text("·").foregroundStyle(t.label2)
                        Button(showOriginal ? LocalizedStringKey("Show Translation") : LocalizedStringKey("Show Original")) { showOriginal.toggle() }
                            .buttonStyle(.plain).foregroundStyle(t.accentText)
                    }
                    .font(t.font(11))
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(t.fill2, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.rS, style: .continuous).strokeBorder(t.sep, lineWidth: 1))

            HStack(alignment: .center, spacing: 8) {
                Text("Suggested reply").font(t.font(13, .semibold))
                Text("Drafted by \(AISettings.provider.title) in \(ReviewInfo.languageName(lang))").font(t.font(11)).foregroundStyle(t.label2)
                Spacer()
                GlassSegments(options: [("Friendly", String(localized: "Friendly")), ("Brief", String(localized: "Brief"))], selection: $tone).fixedSize()
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text).font(t.font(13)).lineSpacing(3).scrollContentBackground(.hidden).focused($focused)
                    .padding(8).frame(height: 132)
                if busy && text.isEmpty {
                    Text("Drafting…").font(t.font(13)).foregroundStyle(t.label3).padding(.horizontal, 13).padding(.vertical, 8)
                }
            }
            .background(t.field, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.rS, style: .continuous).strokeBorder(focused ? t.accent : t.sep2, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: t.rS + 3, style: .continuous).fill(focused ? t.accentSoft : .clear).padding(-3))
            HStack(alignment: .top) {
                Text(error ?? String(localized: "Replies are public, so review before sending.")).font(t.font(11)).foregroundStyle(error == nil ? t.label2 : t.neg)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text("\(Num.int(Double(text.count))) / 5,970").font(t.font(11)).monospacedDigit().foregroundStyle(text.count > 5970 ? t.neg : t.label2)
            }
            HStack(spacing: 8) {
                SmallButton(label: busy ? String(localized: "Drafting…") : String(localized: "Regenerate"), symbol: "sparkles", busy: busy) { Task { await draft() } }
                Spacer()
                SmallButton(label: String(localized: "Cancel")) { close() }.keyboardShortcut(.cancelAction)
                SmallButton(label: model.isDemo ? String(localized: "Send Reply (demo)") : String(localized: "Send Reply"), prominent: true) { Task { await send() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 5970)
            }
            .padding(.top, 4)
        }
        .frame(width: 552)
        .onAppear {
            text = review.response ?? ""
            if text.isEmpty { Task { await draft() } }
            // Translate right away only when Apple's language pack is already on the Mac; otherwise wait for a click
            // (the system would show its download prompt over the sheet).
            if lang != "en" {
                Task {
                    let status = await LanguageAvailability().status(from: Locale.Language(identifier: lang), to: Locale.Language(identifier: "en"))
                    if status == .installed { config = .init(target: Locale.Language(identifier: "en")) }
                }
            }
        }
        .onChange(of: tone) { if text == lastDraft { Task { await draft() } } }
        .translationTask(config) { session in
            translation = try? await session.translate(review.body).targetText
            config = nil
        }
    }

    private func draft() async {
        busy = true; error = nil; defer { busy = false }
        let style = tone == "Brief" ? "Two sentences at most." : "Warm and specific, three to five sentences."
        do {
            let reply = try await AISettings.assistant.ask(
                "Write a reply to this App Store review in \(ReviewInfo.languageName(lang)). \(style) Address the actual problem, no 'Dear user', no promises you can't keep. Return only the reply text.",
                context: "App: \(model.app?.name ?? "")\nReviewer: \(review.reviewer)\nRating: \(review.rating)/5\nVersion: \(version ?? "unknown")\nTitle: \(review.title)\nReview: \(review.body)")
            text = reply; lastDraft = reply
        } catch { self.error = error.localizedDescription }
    }

    private func send() async {
        busy = true; defer { busy = false }
        do {
            if let syncer = model.syncer { try await syncer.reply(to: review.id, text) }
            else { try model.store.setResponse(review: review.id, text) }
            model.revision += 1
            close()
        } catch { self.error = error.localizedDescription }
    }
}
