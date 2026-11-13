import AlmanacCore
import SwiftUI

/// Territories: first-time downloads choropleth, three takeaways, sortable table (top 9 + Show All).
struct TerritoriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @AppStorage("period") private var days = 28
    @State private var sort: Key = .downloads
    @State private var ascending = false
    @State private var showAll = false

    enum Key: String, CaseIterable { case name = "Territory", impressions = "Impressions", conversion = "Conversion", downloads = "Downloads", change = "Change", share = "Share"
        var title: String {
            switch self {
            case .name: String(localized: "Territory")
            case .impressions: String(localized: "Impressions")
            case .conversion: String(localized: "Conversion")
            case .downloads: String(localized: "Downloads")
            case .change: String(localized: "Change")
            case .share: String(localized: "Share")
            }
        }
    }

    var body: some View {
        let d = TerritoryData(store: model.store, app: model.appId ?? "", days: days)
        Screen(title: String(localized: "Territories"), subtitle: "\(model.app?.name ?? "") · \(String(localized: "First-time downloads")) · \(AppStoreData.md(d.from)) – \(AppStoreData.md(d.to))", inspector: true, scrolls: false) {
            GlassSegments(options: [(7, String(localized: "7 Days")), (28, String(localized: "28 Days")), (90, String(localized: "90 Days")), (365, String(localized: "Year"))], selection: $days)
        } content: {
            // Same proportions at every window size: the map takes ~45% of the height, the table the rest,
            // with as many rows as fit. Full screen gets a bigger map and more rows, never a hole.
            GeometryReader { g in
                let mapH = max(300, (g.size.height - 16) * 0.45)
                let tableH = g.size.height - 16 - mapH
                VStack(alignment: .leading, spacing: 16) {
                    mapCard(d).frame(height: mapH)
                    table(d, height: tableH)
                }
            }
        }
        .onAppear { model.chatContext = d.chatContext }
        .onChange(of: days) { model.chatContext = d.chatContext }
    }

    // MARK: Map + takeaways

    private func mapCard(_ d: TerritoryData) -> some View {
        let bins = ThemedWorldMap.bins(d.rows.map(\.downloads).max() ?? 0)
        return HStack(alignment: .top, spacing: 24) {
            ThemedWorldMap(values: Dictionary(uniqueKeysWithValues: d.rows.map { ($0.code, $0.downloads) }), bins: bins)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Downloads by territory").font(t.font(15, .bold))
                    Text("\(d.rows.filter { $0.downloads > 0 }.count) with downloads").font(t.font(11)).foregroundStyle(t.label2)
                }
                .padding(.bottom, 12)
                if let top = d.largest {
                    takeaway(String(localized: "Largest market"), Text(top.name), String(localized: "\(Num.int(top.downloads)) downloads · \(Num.pct(top.share)) of all"))
                }
                if d.largest != nil && !d.hasPrevious {
                    note(String(localized: "Fastest growing"), days == 365 ? String(localized: "Needs a full earlier year of history to compare") : String(localized: "Needs a full earlier \(days) days of history to compare"))
                }
                if d.largest != nil && d.rows.allSatisfy({ $0.pageViews == nil }) {
                    note(String(localized: "Highest conversion"), String(localized: "Arrives with Apple's first analytics report"))
                }
                if let g = d.fastest {
                    takeaway(String(localized: "Fastest growing"), Text(g.row.name) + Text("  " + g.change.text).foregroundStyle(g.change.color(t)),
                             String(localized: "\(Num.int(g.row.downloads)) downloads, up from \(Num.int(g.row.previous ?? 0))"))
                }
                if let c = d.bestConversion {
                    takeaway(String(localized: "Highest conversion"), Text("\(c.name) \(Num.pct(c.conversion ?? 0))"),
                             String(localized: "Average across territories \(Num.pct(d.averageConversion ?? 0))"))
                }
                if d.largest == nil {
                    Text("No downloads in this period yet.").font(t.font(13)).foregroundStyle(t.label2).padding(.top, 12)
                }
                Spacer(minLength: 12)
                legend(bins)
            }
            .frame(width: 300)
        }
        .frame(maxHeight: .infinity)
        .themedCard(padding: 24)
    }

    private func takeaway(_ label: String, _ value: Text, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(t.font(11)).foregroundStyle(t.label2)
            value.font(t.font(17, .bold)).monospacedDigit().lineLimit(1)
            Text(sub).font(t.font(11)).foregroundStyle(t.label2).monospacedDigit().lineLimit(1)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { t.sep.frame(height: 1) }
    }

    private func note(_ label: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(t.font(11)).foregroundStyle(t.label2)
            Text(sub).font(t.font(13)).foregroundStyle(t.label3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { t.sep.frame(height: 1) }
    }

    private func legend(_ bins: [Double]) -> some View {
        HStack(spacing: 4) {
            ForEach(bins.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(ThemedWorldMap.ramp(t, i, of: bins.count)).frame(height: 6)
                    Text(i + 1 < bins.count ? (i == 0 ? "\(Num.int(bins[0]))–\(Num.int(bins[1] - 1))" : "\(Num.int(bins[i]))+") : "\(Num.int(bins[i]))+")
                        .font(t.font(10)).foregroundStyle(t.label2).monospacedDigit().lineLimit(1)
                }
            }
        }
    }

    // MARK: Table

    private func sorted(_ rows: [TerritoryData.Row]) -> [TerritoryData.Row] {
        let s: [TerritoryData.Row]
        switch sort {
        case .name: s = rows.sorted { $0.name < $1.name }
        case .impressions: s = rows.sorted { ($0.impressions ?? -1) < ($1.impressions ?? -1) }
        case .conversion: s = rows.sorted { ($0.conversion ?? -1) < ($1.conversion ?? -1) }
        case .downloads, .share: s = rows.sorted { $0.downloads < $1.downloads }
        case .change: s = rows.sorted { ($0.ratio ?? -.infinity) < ($1.ratio ?? -.infinity) }
        }
        return ascending ? s : s.reversed()
    }

    private static let widths: [Key: CGFloat?] = [.name: nil, .impressions: 110, .conversion: 100, .downloads: 100, .change: 90, .share: 200]

    private func table(_ d: TerritoryData, height: CGFloat) -> some View {
        let rows = sorted(d.rows)
        let fit = max(3, Int((height - 36 - 40) / 32))
        let shown = showAll ? rows : Array(rows.prefix(fit))
        // Rows share the leftover height so the last one sits on the footer, no gap.
        let rowH = showAll || shown.count < fit ? 32 : (height - 36 - 40) / CGFloat(fit)
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                ForEach(Key.allCases, id: \.self) { k in
                    Button {
                        if sort == k { ascending.toggle() } else { sort = k; ascending = k == .name }
                    } label: {
                        Text(sort == k ? "\(k.title) \(ascending ? "▴" : "▾")" : k.title)
                            .font(t.font(12, .semibold)).foregroundStyle(sort == k ? t.label : t.label2)
                            .frame(maxWidth: .infinity, alignment: k == .name || k == .share ? .leading : .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: Self.widths[k] ?? nil)
                }
            }
            .lineLimit(1).padding(.horizontal, 16).frame(height: 36)
            .overlay(alignment: .bottom) { t.sep.frame(height: 1) }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                        row(r, max: rows.map(\.share).max() ?? 1, height: rowH)
                            .background(i % 2 == 1 ? t.fill2 : .clear)
                    }
                }
            }
            .scrollIndicators(.never).scrollDisabled(!showAll)
            .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                (showAll ? Text("All \(rows.count) territories") : Text("Top \(shown.count) of \(rows.count) territories"))
                    .font(t.font(12)).foregroundStyle(t.label2)
                Spacer()
                if rows.count > fit {
                    Button(showAll ? LocalizedStringKey("Show Top \(fit)") : LocalizedStringKey("Show All")) { showAll.toggle() }
                        .buttonStyle(.plain).font(t.font(12, .semibold)).foregroundStyle(t.accentText)
                }
            }
            .padding(.horizontal, 16).frame(height: 40)
            .overlay(alignment: .top) { t.sep.frame(height: 1) }
        }
        .frame(height: height)
        .themedCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: t.r, style: .continuous))
    }

    private func row(_ r: TerritoryData.Row, max: Double, height: CGFloat) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Text(Territories.flag(r.code)).font(.system(size: 14))
                Text(r.name).font(t.font(13, .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cell(r.impressions.map(Num.int) ?? "—", .impressions, dim: r.impressions == nil)
            cell(r.conversion.map(Num.pct) ?? "—", .conversion, dim: r.conversion == nil)
            Text(Num.int(r.downloads)).font(t.font(13, .bold)).monospacedDigit()
                .frame(width: Self.widths[.downloads]!, alignment: .trailing)
            let c = r.change
            Text(c?.text ?? (r.previous == nil ? "—" : String(localized: "New"))).font(t.font(13)).monospacedDigit()
                .foregroundStyle(c.map { $0.color(t) } ?? (r.previous == nil ? t.label3 : t.label2))
                .frame(width: Self.widths[.change]!, alignment: .trailing)
            HStack(spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(t.fill)
                        Capsule().fill(t.accent).frame(width: max > 0 ? g.size.width * r.share / max : 0)
                    }
                }
                .frame(height: 6)
                Text(Num.pct(r.share)).font(t.font(12)).foregroundStyle(t.label2).monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: Self.widths[.share]!)
        }
        .lineLimit(1)
        .padding(.horizontal, 16).frame(height: height)
    }

    private func cell(_ s: String, _ k: Key, dim: Bool) -> some View {
        Text(s).font(t.font(13)).monospacedDigit().foregroundStyle(dim ? t.label3 : t.label)
            .frame(width: Self.widths[k]!, alignment: .trailing)
    }
}

/// Per-territory numbers for the period. Change only when history covers the previous period.
struct TerritoryData {
    struct Row: Identifiable {
        let code: String, downloads: Double, previous: Double?, impressions: Double?, pageViews: Double?, share: Double
        var id: String { code }
        var name: String { Territories.name(code) }
        var conversion: Double? { pageViews.flatMap { $0 > 0 ? downloads / $0 : nil } }
        var ratio: Double? { previous.flatMap { $0 > 0 ? downloads / $0 - 1 : nil } }
        var change: Change? { previous.flatMap { $0 > 0 ? Change(.firstDownloads, value: downloads, previous: $0, arrows: false) : nil } }
    }

    let from: String, to: String
    let rows: [Row]
    let hasPrevious: Bool
    let appName: String

    init(store: Store, app: String, days: Int) {
        to = store.lastDay(app, .firstDownloads) ?? Day.today()
        from = Day.add(-(days - 1), to: to)
        let pTo = Day.add(-1, to: from), pFrom = Day.add(-(days - 1), to: pTo)
        let fd = store.byTerritory(app, .firstDownloads, from: from, to: to)
        let hasPrev = store.series(app, .firstDownloads, from: pFrom, to: pTo).first.map { Day.between(pFrom, $0.day) <= 1 } ?? false
        hasPrevious = hasPrev
        let prev = hasPrev ? store.byTerritory(app, .firstDownloads, from: pFrom, to: pTo) : [:]
        // Impressions and page views come from the analytics report; nil means not available yet.
        let hasAnalytics = store.lastDay(app, .impressions) != nil
        let imp = store.byTerritory(app, .impressions, from: from, to: to), pv = store.byTerritory(app, .pageViews, from: from, to: to)
        let total = max(fd.values.reduce(0, +), 1)
        rows = Set(fd.keys).union(imp.keys).map { c in
            Row(code: c, downloads: fd[c] ?? 0, previous: hasPrev ? (prev[c] ?? 0) : nil,
                impressions: hasAnalytics ? (imp[c] ?? 0) : nil, pageViews: hasAnalytics ? (pv[c] ?? 0) : nil,
                share: (fd[c] ?? 0) / total)
        }
        appName = app
    }

    var largest: Row? { rows.filter { $0.downloads > 0 }.max { $0.downloads < $1.downloads } }

    /// Highest growth among territories big enough for the % to mean something.
    var fastest: (row: Row, change: Change)? {
        let floor = max(20, (largest?.downloads ?? 0) * 0.05)
        guard let r = rows.filter({ ($0.previous ?? 0) >= floor && ($0.ratio ?? 0) > 0 }).max(by: { $0.ratio! < $1.ratio! }), let c = r.change else { return nil }
        return (r, c)
    }

    var bestConversion: Row? { rows.filter { ($0.pageViews ?? 0) >= 100 }.max { $0.conversion! < $1.conversion! } }

    var averageConversion: Double? {
        let pv = rows.compactMap(\.pageViews).reduce(0, +)
        return pv > 0 ? rows.filter { $0.pageViews != nil }.map(\.downloads).reduce(0, +) / pv : nil
    }

    var chatContext: String {
        "Screen: Territories (first-time downloads), \(from) to \(to)\n" + rows.sorted { $0.downloads > $1.downloads }.prefix(40).map {
            "\($0.name): downloads \(Int($0.downloads)), share \(Num.pct($0.share)), impressions \($0.impressions.map { String(Int($0)) } ?? "n/a"), conversion \($0.conversion.map(Num.pct) ?? "n/a"), change vs previous period \($0.change?.text ?? "n/a")"
        }.joined(separator: "\n")
    }
}

/// Natural Earth projected choropleth: 5 bins of accent mixed into the theme's map base.
struct ThemedWorldMap: View {
    @Environment(\.theme) private var t
    var values: [String: Double]
    var bins: [Double]
    @State private var hovered: String?
    @State private var hoverPoint: CGPoint = .zero

    /// Projected shapes in a unit box (width 1), Antarctica dropped. Computed once.
    private static let shapes: (paths: [(iso: String, path: Path)], aspect: CGFloat) = {
        func project(_ lon: Double, _ lat: Double) -> CGPoint {
            let l = lon * .pi / 180, p = lat * .pi / 180, p2 = p * p, p4 = p2 * p2
            let x = l * (0.8707 - 0.131979 * p2 + p4 * (-0.013791 + p4 * (0.003971 * p2 - 0.001529 * p4)))
            let y = p * (1.007226 + p2 * (0.015085 + p4 * (-0.044475 + 0.028874 * p2 - 0.005916 * p4)))
            return CGPoint(x: x, y: -y)
        }
        let raw = WorldMap.countries.filter { $0.iso != "AQ" }.map { c -> (String, Path) in
            var path = Path()
            for ring in c.rings where ring.count > 2 {
                path.addLines(ring.map { project($0[0], $0[1]) })
                path.closeSubpath()
            }
            return (c.iso, path)
        }
        let box = raw.reduce(CGRect.null) { $0.union($1.1.boundingRect) }
        let s = 1 / box.width
        let tf = CGAffineTransform(scaleX: s, y: s).translatedBy(x: -box.minX, y: -box.minY)
        return (raw.map { ($0.0, $0.1.applying(tf)) }, box.height / box.width)
    }()

    /// Lower bounds of 5 rounded, log-spaced bins up to the max.
    static func bins(_ maxV: Double) -> [Double] {
        guard maxV >= 5 else { return [1] }
        return (0..<5).map { i -> Double in
            let raw = pow(maxV, Double(i) / 5)
            let mag = pow(10, floor(log10(max(raw, 1))))
            return max(1, (raw / mag).rounded(.down) * mag)
        }.reduce(into: [Double]()) { if $0.last != $1 { $0.append($1) } }
    }

    static func ramp(_ t: AlmanacTheme, _ i: Int, of n: Int) -> Color {
        let steps = [0.2, 0.34, 0.5, 0.7, 0.92]
        let k = n <= 1 ? 4 : Int((Double(i) / Double(n - 1) * 4).rounded())
        let base = t.scheme == .dark ? Color(css: "#37373B") : Color(css: "#E8E8EC")
        return base.mix(with: t.accent, by: steps[k])
    }

    private func color(_ v: Double) -> Color {
        guard v > 0 else { return t.mapBase }
        return Self.ramp(t, bins.lastIndex { v >= $0 } ?? 0, of: bins.count)
    }

    var body: some View {
        GeometryReader { g in
            let w = min(g.size.width, g.size.height / Self.shapes.aspect)
            let size = CGSize(width: w, height: w * Self.shapes.aspect)
            let tf = CGAffineTransform(scaleX: w, y: w)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let card = t.scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.9)
                    for s in Self.shapes.paths {
                        let p = s.path.applying(tf)
                        ctx.fill(p, with: .color(color(values[s.iso] ?? 0)))
                        ctx.stroke(p, with: .color(card), lineWidth: 0.5)
                    }
                    if let h = hovered, let s = Self.shapes.paths.first(where: { $0.iso == h }) {
                        ctx.stroke(s.path.applying(tf), with: .color(t.label), lineWidth: 1)
                    }
                }
                .frame(width: size.width, height: size.height)
                .onContinuousHover { phase in
                    if case .active(let p) = phase {
                        hoverPoint = p
                        hovered = Self.shapes.paths.first { $0.path.applying(tf).contains(p) }?.iso
                    } else { hovered = nil }
                }
                if let h = hovered {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Territories.flag(h)) \(Territories.name(h))").font(t.font(12, .semibold))
                        Text(values[h].map { String(localized: "\(Num.int($0)) downloads") } ?? String(localized: "No downloads")).font(t.font(11)).monospacedDigit().foregroundStyle(t.label2)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(t.popover, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: t.rS, style: .continuous).strokeBorder(t.sep2, lineWidth: 1))
                    .fixedSize()
                    .offset(x: min(hoverPoint.x + 12, size.width - 170), y: max(hoverPoint.y - 48, 0))
                    .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
