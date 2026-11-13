import SwiftUI
import WidgetKit

struct Entry: TimelineEntry { var date: Date; var snap: VaneSnapshot }

/// One entry from the snapshot; the app asks WidgetKit to reload after each sync.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snap: context.isPreview ? .sample : VaneSnapshot.load() ?? .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now, snap: VaneSnapshot.load() ?? .sample)], policy: .never))
    }
}

@main
struct VaneWidgets: WidgetBundle {
    var body: some Widget { DownloadsWidget(); ReviewsWidget() }
}

struct DownloadsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "downloads", provider: Provider()) { DownloadsView(snap: $0.snap) }
            .configurationDisplayName("Downloads")
            .description("Yesterday's first-time downloads, and the last 28 days.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct ReviewsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reviews", provider: Provider()) { ReviewsView(snap: $0.snap) }
            .configurationDisplayName("Reviews")
            .description("Average rating and the reviews still waiting for a reply.")
            .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private extension VaneSnapshot {
    var tint: Color { accent.count == 3 ? Color(red: accent[0], green: accent[1], blue: accent[2]) : .indigo }
}

struct DownloadsView: View {
    @Environment(\.widgetFamily) private var family
    var snap: VaneSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(snap.downloads) downloads \(snap.change ?? "")")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text("Downloads · \(snap.day)").font(.caption2).widgetAccentable()
                Text(snap.downloads).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                if let c = snap.change { Text(c).font(.caption2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        case .systemMedium:
            HStack(spacing: 14) {
                yesterday
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 28 days").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(snap.month, id: \.label) { s in
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.label).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(s.value).font(.subheadline.weight(.bold)).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .containerBackground(.background, for: .widget)
        default:
            yesterday.containerBackground(snap.tint, for: .widget)
        }
    }

    /// The small widget, and the left half of the medium one: the hero card from Today.
    private var yesterday: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Downloads · \(snap.day)").font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
            Text(snap.downloads).font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            if let c = snap.change { Text(c).font(.caption.weight(.bold)) }
            Spacer(minLength: 4)
            Spark(values: snap.spark).stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(height: 26)
        }
        .foregroundStyle(.white)
        .padding(family == .systemMedium ? 12 : 0)
        .frame(maxWidth: family == .systemMedium ? 150 : .infinity, maxHeight: .infinity, alignment: .leading)
        .background(family == .systemMedium ? AnyShapeStyle(snap.tint) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ReviewsView: View {
    @Environment(\.widgetFamily) private var family
    var snap: VaneSnapshot

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: snap.rating ?? 0, in: 0...5) {
                Image(systemName: "star.fill")
            } currentValueLabel: {
                Text(snap.rating.map { String(format: "%.1f", $0) } ?? "–")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rating").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(snap.rating.map { String(format: "%.1f", $0) } ?? "–").font(.system(size: 38, weight: .heavy, design: .rounded))
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: Double(i) <= (snap.rating ?? 0).rounded() ? "star.fill" : "star").font(.system(size: 10))
                    }
                }
                .foregroundStyle(snap.tint)
                Spacer(minLength: 4)
                Text(snap.needsReply == 0 ? String(localized: "Every review answered") : String(localized: "\(snap.needsReply) waiting for a reply"))
                    .font(.caption.weight(.semibold)).foregroundStyle(snap.needsReply == 0 ? Color.secondary : snap.tint)
                Text("\(snap.reviews) reviews").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.background, for: .widget)
        }
    }
}

/// Line through the values, scaled to the frame.
struct Spark: Shape {
    var values: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return p }
        let span = max(hi - lo, 1)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: r.maxY - r.height * CGFloat((v - lo) / span))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}
