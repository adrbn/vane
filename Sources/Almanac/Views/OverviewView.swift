import AlmanacCore
import SwiftUI

/// Tile grid for "App Store" (funnel) and "Usage" (engagement). Each tile opens its chart.
struct OverviewView: View {
    enum Kind { case appStore, usage }
    @Environment(AppModel.self) private var model
    var kind: Kind
    @State private var days = 30

    private var metrics: [Metric] {
        switch kind {
        case .appStore: [.impressions, .uniqueImpressions, .pageViews, .ttr, .firstDownloads, .redownloads, .downloads, .pageCR, .browseImpressions, .searchImpressions]
        case .usage: [.sessions, .crashes, .activeSubs, .newRatings, .ratingsTotal]
        }
    }

    var body: some View {
        let app = model.appId ?? ""
        let to = model.store.lastDay(app) ?? Day.today()
        let from = Day.add(-(days - 1), to: to)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PeriodPicker(days: $days)
                    Text("\(Day.date(from).formatted(.dateTime.month(.abbreviated).day())) – \(Day.date(to).formatted(.dateTime.month(.abbreviated).day().year())), compared with the \(days) days before")
                        .font(.callout).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(metrics) { MetricTile(metric: $0, from: from, to: to) }
                }
                if kind == .appStore { Funnel(app: app, from: from, to: to) }
            }
            .padding(20)
        }
        .onAppear {
            model.chatContext = "Screen: \(kind == .appStore ? "App Store funnel" : "Usage") for \(model.app?.name ?? ""), \(from) to \(to)\n"
                + metrics.map { m in
                    let v = model.store.total(app, m, from: from, to: to)
                    let p = model.store.total(app, m, from: Day.add(-days, to: from), to: Day.add(-1, to: from))
                    return "- \(m.title): \(m.format(v)) (previous \(days) days: \(m.format(p)))"
                }.joined(separator: "\n")
        }
    }
}

/// Impressions → page views → downloads, drawn as proportional bars.
struct Funnel: View {
    @Environment(AppModel.self) private var model
    var app: String, from: String, to: String

    var body: some View {
        let steps: [(String, Double)] = [
            ("Impressions", model.store.total(app, .impressions, from: from, to: to)),
            ("Product page views", model.store.total(app, .pageViews, from: from, to: to)),
            ("Downloads", model.store.total(app, .downloads, from: from, to: to)),
        ]
        let top = max(steps[0].1, 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("Funnel").font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 12) {
                    Text(s.0).frame(width: 150, alignment: .leading).foregroundStyle(.secondary)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 4).fill((model.app?.tint ?? .accentColor).opacity(0.85 - Double(i) * 0.2))
                            .frame(width: max(4, g.size.width * sqrt(s.1 / top)))
                    }
                    .frame(height: 18)
                    Text(Int(s.1).formatted()).monospacedDigit().frame(width: 90, alignment: .trailing)
                    Text(i == 0 ? "" : String(format: "%.1f%%", steps[i - 1].1 > 0 ? s.1 / steps[i - 1].1 * 100 : 0))
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                }
            }
            Text("Bar widths use a square-root scale so small steps stay visible.").font(.caption).foregroundStyle(.tertiary)
        }
        .card(padding: 16)
    }
}
