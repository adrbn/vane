import AlmanacCore
import Charts
import SwiftUI

extension AppRecord {
    var tint: Color { Color(hue: hue, saturation: 0.62, brightness: 0.86) }
}

extension InsightCategory {
    var tint: Color {
        switch self {
        case .discovery: .blue
        case .conversion: .indigo
        case .revenue: .green
        case .ratings: .orange
        case .markets: .teal
        case .retention: .pink
        case .milestones: .purple
        case .reports: .gray
        }
    }
}

extension Color {
    #if os(macOS)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let fieldFill = Color(nsColor: .textBackgroundColor)
    #else
    static let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
    static let fieldFill = Color(uiColor: .systemBackground)
    #endif
}

extension View {
    /// Checkbox on the Mac, switch on iOS.
    @ViewBuilder func checkboxStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        self
        #endif
    }

    /// Link-looking button on the Mac, borderless on iOS.
    @ViewBuilder func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}

/// Card surface shared by insights, tiles and report KPIs: one radius, one fill, one hairline.
struct Card: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(Card(padding: padding)) }
}

struct AppIconView: View {
    @Environment(AppModel.self) private var model
    var app: AppRecord
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let url = model.revision >= 0 ? model.store.meta("icon_\(app.id)").flatMap(URL.init(string:)) : nil {
                AsyncImage(url: url) { $0.resizable() } placeholder: { fallback }
            } else { fallback }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
    }

    private var fallback: some View {
        LinearGradient(colors: [app.tint, Color(hue: app.hue + 0.06, saturation: 0.7, brightness: 0.7)], startPoint: .top, endPoint: .bottom)
            .overlay(Text(String(app.name.prefix(1))).font(.system(size: size * 0.5, weight: .semibold, design: .rounded)).foregroundStyle(.white))
    }
}

struct ChangeLabel: View {
    var change: Double?
    var invert = false   // for metrics where down is good (crashes)
    var body: some View {
        if let c = change, c.isFinite {
            let good = invert ? c < 0 : c >= 0
            Label(String(format: "%.1f%%", abs(c) * 100), systemImage: c >= 0 ? "arrow.up" : "arrow.down")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(abs(c) < 0.005 ? Color.secondary : good ? Color.green : Color.red)
        } else {
            Text("No earlier data").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct Sparkline: View {
    var points: [Point]
    var tint: Color
    var bars = false

    var body: some View {
        Chart(points) { p in
            if bars {
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value)).foregroundStyle(tint.opacity(0.75))
            } else {
                AreaMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .foregroundStyle(.linearGradient(colors: [tint.opacity(0.22), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value)).foregroundStyle(tint).lineStyle(.init(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: bars))
    }
}

/// A metric over a period with its change and a sparkline. Clicking opens the full chart.
struct MetricTile: View {
    @Environment(AppModel.self) private var model
    var metric: Metric
    var from: String
    var to: String

    var body: some View {
        let app = model.appId ?? ""
        let span = Day.between(from, to) + 1
        let value = model.store.total(app, metric, from: from, to: to)
        let prev = model.store.total(app, metric, from: Day.add(-span, to: from), to: Day.add(-1, to: from))
        Button { model.section = .metric(metric) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(metric.title).font(.subheadline).foregroundStyle(.secondary)
                Text(metric.format(value)).font(.title2.weight(.semibold)).monospacedDigit()
                ChangeLabel(change: prev > 0 ? value / prev - 1 : nil, invert: metric == .crashes)
                Sparkline(points: sparkPoints(app), tint: model.app?.tint ?? .accentColor)
                    .frame(height: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id("\(metric.rawValue)\(model.revision)")
    }

    /// Sparse counts (a few ratings a day) zigzag between 0 and 1; weekly sums read better.
    private func sparkPoints(_ app: String) -> [Point] {
        let points = model.store.series(app, metric, from: from, to: to)
        return metric == .newRatings && points.count > 14 ? points.bucketed(.week) : points
    }
}

struct PeriodPicker: View {
    @Binding var days: Int
    var body: some View {
        Picker("Period", selection: $days) {
            Text("Last 7 days").tag(7)
            Text("Last 30 days").tag(30)
            Text("Last 90 days").tag(90)
            Text("Last 12 months").tag(365)
        }
        .labelsHidden()
        .fixedSize()
    }
}

struct EmptyHint: View {
    var title: String, message: String, symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}
