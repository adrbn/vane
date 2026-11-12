import AlmanacCore
import SwiftUI

struct TerritoryRow: Identifiable {
    var code: String
    var impressions: Double, pageViews: Double, firstDownloads: Double, redownloads: Double, sales: Double
    var change: Double, share: Double
    var id: String { code }
    var name: String { Territories.name(code) }
    var conversion: Double { pageViews > 0 ? (firstDownloads + redownloads) / pageViews : 0 }
}

struct LegacyTerritoriesView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 7
    @State private var sortOrder = [KeyPathComparator(\TerritoryRow.impressions, order: .reverse)]

    var body: some View {
        let app = model.appId ?? ""
        let to = model.store.lastDay(app) ?? Day.today()
        let from = Day.add(-(days - 1), to: to)
        let rows = makeRows(app: app, from: from, to: to).sorted(using: sortOrder)
        let mapped = mappedColumn
        let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.code, mapped.value($0)) })

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PeriodPicker(days: $days)
                Text("\(rows.count) territories").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 14)
            WorldMap(values: values, tint: model.app?.tint ?? .accentColor, format: mapped.format)
                .frame(minHeight: 260, maxHeight: 400)
                .card(padding: 10)
                .padding(.horizontal, 20).padding(.vertical, 12)
            Text("Map shows \(mapped.title.lowercased()). Click a column header to map a different one.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 6)
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Territory", value: \.name) { r in Text("\(Territories.flag(r.code))  \(r.name)") }
                TableColumn("Impressions", value: \.impressions) { r in num(r.impressions) }
                TableColumn("Page views", value: \.pageViews) { r in num(r.pageViews) }
                TableColumn("Conversion", value: \.conversion) { r in Text(String(format: "%.2f%%", r.conversion * 100)).monospacedDigit() }
                TableColumn("First-time", value: \.firstDownloads) { r in num(r.firstDownloads) }
                TableColumn("Redownloads", value: \.redownloads) { r in num(r.redownloads) }
                TableColumn("Sales", value: \.sales) { r in Text(Metric.sales.format(r.sales)).monospacedDigit() }
                TableColumn("Downloads change", value: \.change) { r in ChangeLabel(change: r.change.isNaN ? nil : r.change) }
                TableColumn("Share", value: \.share) { r in Text(String(format: "%.1f%%", r.share * 100)).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        .onAppear {
            model.chatContext = "Screen: Territories for \(model.app?.name ?? ""), \(from) to \(to)\n"
                + rows.sorted { $0.impressions > $1.impressions }.prefix(40).map {
                    "\($0.name): impressions \(Int($0.impressions)), page views \(Int($0.pageViews)), downloads \(Int($0.firstDownloads + $0.redownloads)), sales \(Metric.sales.format($0.sales)), downloads change vs previous period \($0.change.isNaN ? "n/a" : String(format: "%+.0f%%", $0.change * 100))"
                }.joined(separator: "\n")
        }
    }

    private var mappedColumn: (title: String, value: (TerritoryRow) -> Double, format: (Double) -> String) {
        let int: (Double) -> String = { Int($0).formatted() }
        switch sortOrder.first?.keyPath {
        case \TerritoryRow.pageViews: return ("Page views", \.pageViews, int)
        case \TerritoryRow.firstDownloads: return ("First-time downloads", \.firstDownloads, int)
        case \TerritoryRow.redownloads: return ("Redownloads", \.redownloads, int)
        case \TerritoryRow.sales: return ("Sales", \.sales, { Metric.sales.format($0) })
        case \TerritoryRow.conversion: return ("Conversion", \.conversion, { String(format: "%.2f%%", $0 * 100) })
        default: return ("Impressions", \.impressions, int)
        }
    }

    private func num(_ v: Double) -> some View { Text(Int(v).formatted()).monospacedDigit() }

    private func makeRows(app: String, from: String, to: String) -> [TerritoryRow] {
        let s = model.store
        let imp = s.byTerritory(app, .impressions, from: from, to: to), pv = s.byTerritory(app, .pageViews, from: from, to: to)
        let fd = s.byTerritory(app, .firstDownloads, from: from, to: to), rd = s.byTerritory(app, .redownloads, from: from, to: to)
        let sa = s.byTerritory(app, .sales, from: from, to: to)
        let span = Day.between(from, to) + 1
        let prev = s.byTerritory(app, .downloads, from: Day.add(-span, to: from), to: Day.add(-1, to: from))
        let totalImp = max(imp.values.reduce(0, +), 1)
        return Set(imp.keys).union(fd.keys).union(sa.keys).map { c in
            let dl = (fd[c] ?? 0) + (rd[c] ?? 0)
            let p = prev[c] ?? 0
            return TerritoryRow(code: c, impressions: imp[c] ?? 0, pageViews: pv[c] ?? 0, firstDownloads: fd[c] ?? 0, redownloads: rd[c] ?? 0,
                                sales: sa[c] ?? 0, change: p > 0 ? dl / p - 1 : .nan, share: (imp[c] ?? 0) / totalImp)
        }
    }
}

/// Flat equirectangular choropleth from bundled Natural Earth shapes.
struct WorldMap: View {
    struct Country: Decodable { let iso: String; let name: String; let rings: [[[Double]]] }
    static let countries: [Country] = {
        let candidates = [Bundle.main.url(forResource: "countries", withExtension: "json"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/countries.json")]
        for case let url? in candidates {
            if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode([Country].self, from: d) { return c }
        }
        return []
    }()

    var values: [String: Double]
    var tint: Color
    var format: (Double) -> String
    @State private var hovered: Country?
    @State private var hoverPoint: CGPoint = .zero

    private let latTop = 84.0, latBottom = -57.0

    var body: some View {
        let maxV = values.values.max() ?? 1
        let buckets = Self.buckets(maxV)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let size = fit(g.size)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for c in Self.countries {
                            let path = self.path(c, size)
                            let v = values[c.iso] ?? 0
                            ctx.fill(path, with: .color(color(v, buckets)))
                            ctx.stroke(path, with: .color(Color.cardFill), lineWidth: 0.5)
                        }
                        if let h = hovered { ctx.stroke(self.path(h, size), with: .color(.primary.opacity(0.7)), lineWidth: 1) }
                    }
                    .frame(width: size.width, height: size.height)
                    .onContinuousHover { phase in
                        if case .active(let p) = phase {
                            hoverPoint = p
                            hovered = Self.countries.first { self.path($0, size).contains(p) }
                        } else { hovered = nil }
                    }
                    if let h = hovered {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Territories.flag(h.iso)) \(Territories.name(h.iso))").font(.caption.weight(.semibold))
                            Text(values[h.iso].map(format) ?? "No data").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .offset(x: min(hoverPoint.x + 12, size.width - 150), y: max(hoverPoint.y - 44, 0))
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 12) {
                legend(Color.secondary.opacity(0.15), "None")
                ForEach(Array(buckets.enumerated()), id: \.offset) { i, b in
                    legend(tint.opacity(0.25 + 0.75 * Double(i + 1) / Double(buckets.count)), "\(format(b))+")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(t) }
    }

    /// Lower bounds of 5 log-spaced buckets up to the max.
    static func buckets(_ maxV: Double) -> [Double] {
        guard maxV > 1 else { return [0] }
        let steps = 5.0
        return (0..<Int(steps)).map { i in
            let raw = pow(maxV, Double(i) / steps)
            let mag = pow(10, floor(log10(max(raw, 1))))
            return (raw / mag).rounded(.down) * mag
        }.reduce(into: [Double]()) { if $0.last != $1 { $0.append($1) } }
    }

    private func color(_ v: Double, _ buckets: [Double]) -> Color {
        guard v > 0 else { return Color.secondary.opacity(0.15) }
        let i = buckets.lastIndex { v >= $0 } ?? 0
        return tint.opacity(0.25 + 0.75 * Double(i + 1) / Double(buckets.count))
    }

    private func fit(_ s: CGSize) -> CGSize {
        let ratio = 360 / (latTop - latBottom)
        return s.width / s.height > ratio ? CGSize(width: s.height * ratio, height: s.height) : CGSize(width: s.width, height: s.width / ratio)
    }

    private func path(_ c: Country, _ size: CGSize) -> Path {
        var p = Path()
        for ring in c.rings {
            for (i, pt) in ring.enumerated() {
                let x = (pt[0] + 180) / 360 * size.width
                let y = (latTop - max(min(pt[1], latTop), latBottom)) / (latTop - latBottom) * size.height
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            p.closeSubpath()
        }
        return p
    }
}
