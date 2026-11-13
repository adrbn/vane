#if os(macOS)
import AlmanacCore
import SwiftUI

/// Usage: sessions and crashes (Apple's analytics report), ratings and subscriptions. Four cards share the height;
/// a metric with no data yet says when it arrives instead of showing 0.
struct UsageScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @AppStorage("period") private var days = 28

    var body: some View {
        let app = model.appId ?? ""
        let analytics = model.store.lastDay(app, .sessions) != nil
        let to = model.store.lastDay(app, .sessions) ?? model.store.lastDay(app) ?? Day.today()
        let from = Day.add(-(days - 1), to: to)
        Screen(title: "Usage", subtitle: "\(model.app?.name ?? "") · \(AppStoreData.md(from)) – \(AppStoreData.md(to))", inspector: true, scrolls: false) {
            GlassSegments(options: [(7, "7 Days"), (28, "28 Days"), (90, "90 Days"), (365, "Year")], selection: $days)
        } content: {
            let subs = model.store.series(app, .activeSubs).contains { $0.value > 0 }
            VStack(spacing: 16) {
                if !analytics { AnalyticsPending(compact: true) }
                // Until Apple's report lands, sessions and crashes stay compact and the real data (ratings) takes the room.
                HStack(spacing: 16) {
                    UsageCard(metric: .sessions, from: from, to: to, days: days, pending: analytics ? nil : "Arrives with Apple's first analytics report")
                    UsageCard(metric: .crashes, from: from, to: to, days: days, pending: !analytics ? "Arrives with Apple's first analytics report"
                              : model.store.lastDay(app, .crashes) == nil ? "No crash report from Apple yet." : nil)
                }
                .frame(height: analytics ? nil : 132)
                .frame(maxHeight: analytics ? .infinity : nil)
                HStack(spacing: 16) {
                    RatingsCard()
                    if subs { UsageCard(metric: .activeSubs, from: from, to: to, days: days, pending: nil) }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            model.chatContext = "Screen: Usage for \(model.app?.name ?? ""), \(from) to \(to)\n"
                + [Metric.sessions, .crashes, .activeSubs].map { m in
                    // A metric with no rows at all hasn't arrived from Apple yet: say so instead of passing a misleading 0.
                    model.store.series(app, m).isEmpty ? "- \(m.title): not available yet (waiting for Apple's first analytics report)"
                        : "- \(m.title): \(m.format(model.store.total(app, m, from: from, to: to)))"
                }.joined(separator: "\n")
                + "\n- Ratings on the App Store: \(model.store.series(app, .ratingsTotal).last.map { Num.int($0.value) } ?? "not available yet")"
                + "\n- Written reviews: \(model.store.reviews(app).count), average \(String(format: "%.1f", ReviewInfo.average(model.store.reviews(app))))"
        }
    }
}

private struct UsageCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let metric: Metric, from: String, to: String, days: Int
    let pending: String?

    var body: some View {
        let app = model.appId ?? ""
        // Gauges (ratings, subscriptions) read their latest value even if it's newer than the analytics range.
        let gauge = metric == .ratingsTotal || metric == .activeSubs
        let end = gauge ? max(to, model.store.lastDay(app, metric) ?? to) : to
        let pts = model.store.series(app, metric, from: from, to: end)
        let value = model.store.total(app, metric, from: from, to: end)
        let pTo = Day.add(-1, to: from), pFrom = Day.add(-(days - 1), to: pTo)
        let covered = model.store.series(app, metric, from: "2000-01-01", to: end).first.map { $0.day <= pFrom } ?? false
        let c = covered ? Change(metric, value: value, previous: model.store.total(app, metric, from: pFrom, to: pTo)) : Change.noHistory
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconSquare(symbol: symbol, style: t.square(metric), size: 26)
                Text(title).font(t.font(14, .semibold)).foregroundStyle(t.label2)
            }
            if let pending {
                Text("—").font(t.numFont).foregroundStyle(t.label3).padding(.top, 14)
                Text(pending).font(t.font(13)).foregroundStyle(t.label2).padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                Text(metric.format(value)).font(t.numFont).tracking(-0.9).monospacedDigit().lineLimit(1).padding(.top, 14)
                Text(pts.count < 2 ? "Tracked daily since \(AppStoreData.md(pts.first?.day ?? end))" : c.text == Change.noHistory.text ? c.text : "\(c.text) on the previous \(days) days")
                    .font(t.font(13, .semibold)).foregroundStyle(pts.count < 2 || c.text == Change.noHistory.text ? t.label2 : c.color(t)).monospacedDigit().padding(.top, 4)
                if pts.count >= 2 {
                    ZStack {
                        LinePath(values: pts.map(\.value), floorZero: !gauge, closed: true).fill(t.color(metric).opacity(0.14))
                        LinePath(values: pts.map(\.value), floorZero: !gauge).stroke(t.color(metric), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                    .padding(.top, 16)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedCard()
        .opens { model.section = metric == .ratingsTotal ? .reviews : .metric(metric) }
    }

    private var title: String { metric == .ratingsTotal ? "Ratings" : metric.title }
    private var symbol: String {
        switch metric {
        case .sessions: "play.circle.fill"
        case .crashes: "exclamationmark.triangle.fill"
        case .ratingsTotal: "star.fill"
        default: "creditcard.fill"
        }
    }
}

/// Ratings count from App Store Connect plus the written reviews: average, spread, and the latest one.
private struct RatingsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        let app = model.appId ?? ""
        let reviews = model.store.reviews(app)
        let total = model.store.series(app, .ratingsTotal).last
        let avg = ReviewInfo.average(reviews)
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    IconSquare(symbol: "star.fill", style: t.square(.ratingsTotal), size: 26)
                    Text("Ratings").font(t.font(14, .semibold)).foregroundStyle(t.label2)
                }
                Text(total.map { Num.int($0.value) } ?? "—").font(t.numFont).tracking(-0.9).monospacedDigit()
                    .foregroundStyle(total == nil ? t.label3 : t.label).padding(.top, 14)
                Text(total.map { "Ratings on the App Store, tracked since \(AppStoreData.md($0.day))" } ?? "Counted from the next refresh")
                    .font(t.font(13)).foregroundStyle(t.label2).padding(.top, 4)
                Spacer(minLength: 20)
                Text("Written reviews").font(t.font(13, .semibold)).foregroundStyle(t.label2)
                HStack(spacing: 10) {
                    Text(reviews.isEmpty ? "—" : String(format: "%.1f", avg)).font(t.font(28, t.numWeight)).monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        ThemedStars(rating: Int(avg.rounded()), size: 11)
                        Text("\(reviews.count) review\(reviews.count == 1 ? "" : "s")").font(t.font(11)).foregroundStyle(t.label2)
                    }
                }
                .padding(.top, 4)
                VStack(spacing: 6) {
                    ForEach((1...5).reversed(), id: \.self) { n in
                        let share = reviews.isEmpty ? 0 : Double(reviews.filter { $0.rating == n }.count) / Double(reviews.count)
                        HStack(spacing: 8) {
                            Text("\(n)").font(t.font(11)).foregroundStyle(t.label2).frame(width: 8)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(t.fill)
                                    Capsule().fill(t.accent).frame(width: g.size.width * share)
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
                .padding(.top, 12)
            }
            .frame(width: 260, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Latest reviews").font(t.font(13, .semibold)).foregroundStyle(t.label2)
                    Spacer()
                    SmallButton(label: "Open Reviews") { model.section = .reviews }
                }
                if reviews.isEmpty {
                    Text("No written reviews yet. They show up here and in Reviews as people write them.").font(t.font(13)).foregroundStyle(t.label2)
                }
                ForEach(Array(reviews.prefix(3).enumerated()), id: \.element.id) { i, r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            ThemedStars(rating: r.rating, size: 11)
                            Text(r.title).font(t.font(15, .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(r.body).font(t.font(13)).lineSpacing(3).lineLimit(4)
                        Text("\(r.reviewer) · \(AppStoreData.md(r.created)) · \(r.response == nil ? "Not replied yet" : "Replied")")
                            .font(t.font(12)).foregroundStyle(r.response == nil ? t.warn : t.label2)
                    }
                    .padding(.top, i == 0 ? 4 : 14)
                    .overlay(alignment: .top) { if i > 0 { t.sep.frame(height: 1) } }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedCard()
    }
}
#endif
