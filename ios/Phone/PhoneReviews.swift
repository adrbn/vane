import AlmanacCore
import SwiftUI

/// Reviews: rating summary, All / Needs reply, then the reviews. Replies are typed on the phone (drafting runs on the Mac).
struct PhoneReviews: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var needsReply = false
    @State private var replying: Review?

    var body: some View {
        let _ = model.revision
        let app = model.appId ?? ""
        let all = model.store.reviews(app)
        let versions = model.store.versions(app)
        let shown = needsReply ? all.filter { $0.response == nil } : all
        PhoneScreen(title: "Reviews", subtitle: "\(all.count) review\(all.count == 1 ? "" : "s") · \(all.filter { $0.response == nil }.count) without a reply") {
            summary(all)
            PhoneSegments(options: [(false, "All"), (true, "Needs reply")], selection: $needsReply)
            if shown.isEmpty {
                Text(needsReply ? "Every review has a reply." : "No reviews yet.").font(t.font(13)).foregroundStyle(t.label2).phoneCard()
            }
            ForEach(shown) { r in
                ThemedReviewRow(review: r, version: ReviewInfo.version(r, versions), replying: $replying)
                    .phoneCard(padding: 0)
            }
        }
        .sheet(item: $replying) { r in
            PhoneReplySheet(review: r, version: ReviewInfo.version(r, versions)) { replying = nil }
                .environment(\.theme, t)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(44)
        }
    }

    private func summary(_ all: [Review]) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(all.isEmpty ? "—" : String(format: "%.1f", ReviewInfo.average(all))).font(t.font(48, .heavy)).tracking(-1)
                ThemedStars(rating: Int(ReviewInfo.average(all).rounded()), size: 14)
                Text("\(all.count) reviews").font(t.font(12)).foregroundStyle(t.label2)
            }
            VStack(spacing: 4) {
                ForEach((1...5).reversed(), id: \.self) { s in
                    let n = all.filter { $0.rating == s }.count
                    HStack(spacing: 6) {
                        Text("\(s)").font(t.font(11, .semibold)).foregroundStyle(t.label2).frame(width: 10)
                        GeometryReader { g in
                            Capsule().fill(t.fill)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(t.accent).frame(width: g.size.width * (all.isEmpty ? 0 : CGFloat(n) / CGFloat(all.count)))
                                }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .phoneCard()
    }
}

/// Reply typed on the phone, sent to App Store Connect (or saved locally in the demo).
struct PhoneReplySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var review: Review
    var version: String?
    var close: () -> Void
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Cancel", action: close).font(t.font(16)).foregroundStyle(t.label2)
                Spacer()
                Text("Reply").font(t.font(17, .bold))
                Spacer()
                Button(busy ? "Sending…" : "Send") { Task { await send() } }
                    .font(t.font(16, .semibold)).foregroundStyle(t.accentText)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            .frame(height: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ThemedStars(rating: review.rating)
                    Text(review.title).font(t.font(14, .semibold)).lineLimit(1)
                }
                Text(review.body).font(t.font(13)).foregroundStyle(t.label2).lineLimit(4)
                Text(([review.reviewer, "\(Territories.flag(review.territory)) \(Territories.name(review.territory))"] + (version.map { ["Version \($0)"] } ?? []))
                    .joined(separator: " · ")).font(t.font(11)).foregroundStyle(t.label3)
            }
            .phoneCard(padding: 14)
            TextEditor(text: $text)
                .focused($focused)
                .font(t.font(15)).scrollContentBackground(.hidden)
                .padding(10).frame(minHeight: 140)
                .background(t.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write your reply. Drafting with AI happens in Vane on your Mac.").font(t.font(15)).foregroundStyle(t.label3)
                            .padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
                    }
                }
            if let error { Text(error).font(t.font(12)).foregroundStyle(t.neg) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .foregroundStyle(t.label)
        .background(t.sheet.ignoresSafeArea())
        .preferredColorScheme(t.scheme)
        .onAppear { focused = true }
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
