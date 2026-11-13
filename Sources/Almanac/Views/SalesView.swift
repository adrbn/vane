import AlmanacCore
import Charts
import SwiftUI

struct SalesView: View {
    @Environment(AppModel.self) private var model
    @State private var granularity: Granularity = .week

    struct Row: Identifiable {
        var start: String, sales: Double, proceeds: Double, downloads: Double, subs: Double, releases: String, partial: Bool
        var id: String { start }
    }

    var body: some View {
        let app = model.appId ?? ""
        let last = model.store.lastDay(app) ?? Day.today()
        let span: Int = switch granularity { case .day: 60; case .week: 7 * 52; case .month: 730; case .year: 1825 }
        let from = granularity.bucket(Day.add(-span, to: last))
        let sales = model.store.series(app, .sales, from: from, to: last)
        let rows = makeRows(app: app, from: from, to: last)
        let tint = model.app?.tint ?? .accentColor

        VStack(spacing: 0) {
            HStack {
                Picker("Granularity", selection: $granularity) {
                    ForEach(Granularity.allCases) { Text($0 == .day ? "Daily" : $0.rawValue + "ly").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 14)
            HStack(spacing: 14) {
                summaryTile("Sales", value: Metric.sales.format(sales.suffix(granularity == .day ? 1 : 30).total),
                            caption: granularity == .day ? "Last day" : "Last 30 days",
                            change: change(sales.suffix(30).total, sales.dropLast(30).suffix(30).total),
                            points: sales.bucketed(granularity == .day ? .day : .week).suffix(40), tint: tint)
                let subs = model.store.series(app, .activeSubs, from: from, to: last)
                summaryTile("Active subscriptions", value: Num.int(subs.last?.value ?? 0), caption: "Latest day",
                            change: change(subs.last?.value ?? 0, subs.dropLast(30).last?.value ?? 0),
                            points: subs.bucketed(.week, average: true).suffix(40), tint: tint)
            }
            .padding(20)
            Table(rows) {
                TableColumn(granularity.rawValue) { r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label(r.start)).fontWeight(.medium)
                        if !r.releases.isEmpty { Text(r.releases).font(.caption).foregroundStyle(.blue) }
                        if r.partial { Text("In progress").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                TableColumn("Sales") { r in Text(Metric.sales.format(r.sales)).monospacedDigit() }
                TableColumn("Proceeds") { r in Text(Metric.sales.format(r.proceeds)).monospacedDigit().foregroundStyle(.secondary) }
                TableColumn("Downloads") { r in Text(Num.int(r.downloads)).monospacedDigit() }
                TableColumn("Sales per download") { r in Text(r.downloads > 0 ? Metric.sales.format(r.sales / r.downloads) : "—").monospacedDigit() }
                TableColumn("Active subs") { r in Text(r.subs > 0 ? Num.int(r.subs) : "—").monospacedDigit() }
            }
            #if os(macOS)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            #endif
        }
        .onAppear {
            model.chatContext = "Screen: Sales by \(granularity.rawValue.lowercased()) for \(model.app?.name ?? "") (USD)\n"
                + rows.prefix(60).map { "\($0.start): sales \(Metric.sales.format($0.sales)), proceeds \(Metric.sales.format($0.proceeds)), downloads \(Int($0.downloads)), active subs \(Int($0.subs))\($0.releases.isEmpty ? "" : ", release " + $0.releases)" }
                    .joined(separator: "\n")
        }
    }

    private func makeRows(app: String, from: String, to: String) -> [Row] {
        let s = model.store.series(app, .sales, from: from, to: to).bucketed(granularity)
        let p = Dictionary(uniqueKeysWithValues: model.store.series(app, .proceeds, from: from, to: to).bucketed(granularity).map { ($0.day, $0.value) })
        let d = Dictionary(uniqueKeysWithValues: model.store.series(app, .downloads, from: from, to: to).bucketed(granularity).map { ($0.day, $0.value) })
        var subs: [String: Double] = [:]
        for pt in model.store.series(app, .activeSubs, from: from, to: to) { subs[granularity.bucket(pt.day)] = pt.value } // last value per bucket
        let versions = model.store.versions(app)
        let currentBucket = granularity.bucket(to)
        let bucketEndsAfterData = granularity != .day && granularity.bucket(Day.add(1, to: to)) == currentBucket
        return s.reversed().map { pt in
            Row(start: pt.day, sales: pt.value, proceeds: p[pt.day] ?? 0, downloads: d[pt.day] ?? 0, subs: subs[pt.day] ?? 0,
                releases: versions.filter { granularity.bucket($0.day) == pt.day }.map { "\($0.version)\($0.title.isEmpty ? "" : " — " + $0.title)" }.joined(separator: ", "),
                partial: pt.day == currentBucket && bucketEndsAfterData)
        }
    }

    private func summaryTile(_ title: String, value: String, caption: String, change: Double?, points: ArraySlice<Point>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                ChangeLabel(change: change)
            }
            Text(caption).font(.caption).foregroundStyle(.tertiary)
            Sparkline(points: Array(points), tint: tint, bars: true).frame(height: 56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func change(_ a: Double, _ b: Double) -> Double? { b > 0 ? a / b - 1 : nil }

    private func label(_ day: String) -> String {
        let d = Day.date(day)
        switch granularity {
        case .day: return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            let e = Day.date(Day.add(6, to: day))
            return "\(d.formatted(.dateTime.month(.abbreviated).day())) – \(e.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month: return d.formatted(.dateTime.month(.wide).year())
        case .year: return d.formatted(.dateTime.year())
        }
    }
}
