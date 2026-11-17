import AlmanacCore
import SwiftUI
import Translation

struct LegacyReviewsView: View {
    @Environment(AppModel.self) private var model
    @State private var rating = 0          // 0 = all
    @State private var unansweredOnly = false
    @State private var replying: Review?

    var body: some View {
        let all = model.store.reviews(model.appId ?? "")
        let shown = all.filter { (rating == 0 || $0.rating == rating) && (!unansweredOnly || $0.response == nil) }
        let avg = all.isEmpty ? 0 : Double(all.map(\.rating).reduce(0, +)) / Double(all.count)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(String(format: "%.1f", avg)).font(.title2.weight(.semibold)).monospacedDigit()
                Stars(rating: Int(avg.rounded()))
                Text("\(all.count) reviews").foregroundStyle(.secondary)
                Spacer()
                Picker("Rating", selection: $rating) {
                    Text("All ratings").tag(0)
                    ForEach((1...5).reversed(), id: \.self) { Text("\($0) stars").tag($0) }
                }
                .labelsHidden().fixedSize()
                Toggle("Unanswered only", isOn: $unansweredOnly).checkboxStyle()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if shown.isEmpty {
                EmptyHint(title: "No reviews", message: "Reviews written on the App Store show up here after a refresh.", symbol: "text.bubble")
            } else {
                List(shown) { ReviewRow(review: $0, replying: $replying) }
                    .listStyle(.inset)
            }
        }
        .sheet(item: $replying) { ReplySheet(review: $0) }
        .onAppear {
            model.chatContext = "Screen: Reviews for \(model.app?.name ?? ""), average \(String(format: "%.2f", avg)) over \(all.count)\n"
                + all.prefix(60).map { "[\($0.rating)★ \($0.created) \($0.territory)\($0.response == nil ? "" : ", replied")] \($0.title): \($0.body)" }.joined(separator: "\n")
        }
    }
}

struct Stars: View {
    var rating: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { Image(systemName: $0 <= rating ? "star.fill" : "star").foregroundStyle($0 <= rating ? .orange : .secondary.opacity(0.4)) }
        }
        .font(.caption)
    }
}

struct ReviewRow: View {
    var review: Review
    @Binding var replying: Review?
    @State private var translation: String?
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Stars(rating: review.rating)
                Text(review.title).font(.headline)
                Spacer()
                Text("\(Territories.flag(review.territory)) \(review.reviewer) · \(Day.date(review.created).formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(translation ?? review.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let r = review.response {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(.secondary).font(.caption)
                    Text(r).font(.callout).foregroundStyle(.secondary)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 14) {
                Button(translation == nil ? LocalizedStringKey("Translate") : LocalizedStringKey("Show original")) {
                    if translation != nil { translation = nil } else { config = .init(target: Locale.current.language) }
                }
                Button(review.response == nil ? LocalizedStringKey("Reply…") : LocalizedStringKey("Edit reply…")) { replying = review }
            }
            .linkButtonStyle().font(.caption)
        }
        .padding(.vertical, 6)
        .translationTask(config) { session in
            // Apple's on-device translator: the review never leaves the Mac.
            translation = try? await session.translate(review.body).targetText
            config = nil
        }
    }
}

struct ReplySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var review: Review
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reply to \(review.reviewer)").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Stars(rating: review.rating)
                Text(review.title).font(.headline)
                Text(review.body).foregroundStyle(.secondary)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            TextEditor(text: $text).font(.body).frame(minHeight: 120).scrollContentBackground(.hidden)
                .padding(6).background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Text("\(text.count) / 5,970").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if let error { Text(error).foregroundStyle(.red).font(.caption).lineLimit(2) }
                Spacer()
            }
            HStack {
                Button("Suggest a reply") { Task { await suggest() } }.disabled(busy)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.isDemo ? LocalizedStringKey("Post (demo)") : LocalizedStringKey("Post reply")) { Task { await post() } }
                    .keyboardShortcut(.defaultAction).disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 520)
        .onAppear { text = review.response ?? "" }
    }

    private func suggest() async {
        busy = true; defer { busy = false }
        do {
            text = try await AISettings.assistant.ask(
                "Write a short, warm, specific reply to this review, in the reviewer's language. No greeting like 'Dear user', no sign-off, no promises you can't keep. Return only the reply text.",
                context: "App: \(model.app?.name ?? "")\nRating: \(review.rating)/5\nTitle: \(review.title)\nReview: \(review.body)")
        } catch { self.error = error.localizedDescription }
    }

    private func post() async {
        busy = true; defer { busy = false }
        do {
            if let syncer = model.syncer { try await syncer.reply(to: review.id, text) }
            else { try model.store.setResponse(review: review.id, text) }
            model.revision += 1
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Why chat can't answer yet: it runs the user's own AI command-line tool, never a Vane server.
enum ChatHelp {
    static var missing: String {
        #if os(macOS)
        String(localized: "Chat runs your own \(AISettings.provider.title), and Vane can't find it on this Mac. Install it, sign in once in Terminal, then reopen this panel. You can pick Claude Code or Codex in Settings › Assistant.")
        #else
        String(localized: "Chat runs in the Mac app, with your own Claude Code or Codex. Your numbers are all here; ask from your Mac.")
        #endif
    }
}

enum AISettings {
    static var provider: Assistant.Provider { Assistant.Provider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .claude }
    static var model: String { UserDefaults.standard.string(forKey: "aiModel") ?? "sonnet" }
    static var configDir: String? { UserDefaults.standard.string(forKey: "aiConfigDir").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
    static var assistant: Assistant { Assistant(provider: provider, model: model, configDir: configDir) }
}
