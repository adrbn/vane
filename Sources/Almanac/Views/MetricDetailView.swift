import AlmanacCore
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct MetricDetailView: View {
    @Environment(AppModel.self) private var model
    var metric: Metric
    @State private var days = 90
    @State private var granularity: Granularity = .day
    @State private var compare = false
    @State private var territory = ""
    @State private var hover: Date?

    var body: some View {
        let app = model.appId ?? ""
        let to = model.store.lastDay(app) ?? Day.today()
        let from = Day.add(-(days - 1), to: to)
        let data = model.store.series(app, metric, territory: territory, from: from, to: to).bucketed(granularity, average: metric.isGauge)
        let previous = compare
            ? model.store.series(app, metric, territory: territory, from: Day.add(-365, to: from), to: Day.add(-365, to: to))
                .bucketed(granularity, average: metric.isGauge).map { Point(day: Day.add(365, to: $0.day), value: $0.value) }
            : []
        let versions = model.store.versions(app).filter { $0.day >= from && $0.day <= to }
        let tint = model.app?.tint ?? .accentColor

        VStack(spacing: 0) {
            controls(app: app, from: from, to: to, data: data)
                .padding(.horizontal, 20).padding(.vertical, 12)
            chart(data: data, previous: previous, versions: versions, tint: tint)
                .frame(minHeight: 280)
                .padding(.horizontal, 20).padding(.bottom, 12)
            Table(data.reversed()) {
                TableColumn(granularity == .day ? "Day" : granularity.rawValue) { p in Text(label(p.day)) }
                TableColumn(metric.title) { p in Text(metric.format(p.value)).monospacedDigit() }
                TableColumn("Change") { p in
                    let i = data.firstIndex(of: p) ?? 0
                    if i > 0, data[i - 1].value > 0 { ChangeLabel(change: p.value / data[i - 1].value - 1, invert: metric == .crashes) }
                }
                TableColumn("Release") { p in
                    Text(versions.filter { granularity.bucket($0.day) == p.day }.map { "\($0.version) \($0.title)" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 180)
        }
        .onAppear { model.chatContext = context(data: data, versions: versions) }
        .onChange(of: data) { model.chatContext = context(data: data, versions: versions) }
    }

    /// One row when it fits, two when the chat panel narrows the window. A single fixed-width
    /// row wider than the window sends AppKit into a constraint loop and crashes.
    private func controls(app: String, from: String, to: String, data: [Point]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { filters(app: app, from: from, to: to); Spacer(); actions(data: data) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { filters(app: app, from: from, to: to); Spacer(minLength: 0) }
                HStack(spacing: 10) { Spacer(minLength: 0); actions(data: data) }
            }
        }
    }

    @ViewBuilder private func filters(app: String, from: String, to: String) -> some View {
        PeriodPicker(days: $days).fixedSize()
        if metric.hasTerritories {
            let codes = model.store.byTerritory(app, metric == .downloads ? .firstDownloads : metric, from: from, to: to)
                .sorted { $0.value > $1.value }.prefix(40).map(\.key)
            Picker("Territory", selection: $territory) {
                Text("Worldwide").tag("")
                Divider()
                ForEach(codes, id: \.self) { Text("\(Territories.flag($0)) \(Territories.name($0))").tag($0) }
            }
            .labelsHidden().fixedSize()
        }
        Toggle("Compare with last year", isOn: $compare).toggleStyle(.checkbox).fixedSize()
    }

    @ViewBuilder private func actions(data: [Point]) -> some View {
        Text(metric.format(metric.isGauge ? (data.last?.value ?? 0) : data.total)).font(.title3.weight(.semibold)).monospacedDigit()
        Picker("Granularity", selection: $granularity) {
            ForEach([Granularity.day, .week, .month]) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        Button { model.togglePin(metric) } label: {
            Image(systemName: model.pinned.contains(metric) ? "pin.fill" : "pin")
        }
        .help(model.pinned.contains(metric) ? "Unpin from sidebar" : "Pin to sidebar")
        ShareLink(item: csv(data), preview: SharePreview("\(metric.title).csv")) { Image(systemName: "square.and.arrow.up") }
            .help("Export CSV")
    }

    private func chart(data: [Point], previous: [Point], versions: [VersionMark], tint: Color) -> some View {
        Chart {
            ForEach(previous) { p in
                LineMark(x: .value("Day", p.date), y: .value("Previous year", p.value), series: .value("Series", "Previous year"))
                    .foregroundStyle(.secondary.opacity(0.6)).lineStyle(.init(lineWidth: 1.2, dash: [4, 3]))
            }
            ForEach(data) { p in
                AreaMark(x: .value("Day", p.date), y: .value(metric.title, p.value), series: .value("Series", "Current"))
                    .foregroundStyle(.linearGradient(colors: [tint.opacity(0.18), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", p.date), y: .value(metric.title, p.value), series: .value("Series", "Current"))
                    .foregroundStyle(tint).lineStyle(.init(lineWidth: 1.8))
            }
            ForEach(versions) { v in
                RuleMark(x: .value("Release", Day.date(v.day)))
                    .foregroundStyle(.blue.opacity(0.35)).lineStyle(.init(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) { Text(v.version).font(.caption2).foregroundStyle(.blue) }
            }
            if let hover, let p = data.min(by: { abs($0.date.timeIntervalSince(hover)) < abs($1.date.timeIntervalSince(hover)) }) {
                RuleMark(x: .value("Selected", p.date)).foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(p.day)).font(.caption2).foregroundStyle(.secondary)
                            Text(metric.format(p.value)).font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                PointMark(x: .value("Selected", p.date), y: .value(metric.title, p.value)).foregroundStyle(tint)
            }
        }
        .chartXSelection(value: $hover)
        .chartYAxis { AxisMarks { v in
            AxisGridLine()
            AxisValueLabel { if let d = v.as(Double.self) { Text(metric.isRate ? String(format: "%.0f%%", d * 100) : d.formatted(.number.notation(.compactName))) } }
        } }
    }

    private func label(_ day: String) -> String {
        let d = Day.date(day)
        switch granularity {
        case .day: return d.formatted(.dateTime.month(.abbreviated).day().year())
        case .week: return "Week of " + d.formatted(.dateTime.month(.abbreviated).day())
        case .month: return d.formatted(.dateTime.month(.wide).year())
        case .year: return d.formatted(.dateTime.year())
        }
    }

    private func csv(_ data: [Point]) -> String {
        "date,\(metric.rawValue)\n" + data.map { "\($0.day),\($0.value)" }.joined(separator: "\n")
    }

    private func context(data: [Point], versions: [VersionMark]) -> String {
        var s = "Screen: \(metric.title) chart for \(model.app?.name ?? ""), \(territory.isEmpty ? "worldwide" : Territories.name(territory)), by \(granularity.rawValue.lowercased())\n"
        s += data.map { "\($0.day): \(metric.format($0.value))" }.joined(separator: "\n")
        if !versions.isEmpty { s += "\nReleases: " + versions.map { "\($0.version) on \($0.day) \($0.title)" }.joined(separator: "; ") }
        return s
    }
}
