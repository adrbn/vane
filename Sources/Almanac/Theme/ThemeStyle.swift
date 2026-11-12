import AlmanacCore
import SwiftUI

/// Typed access to the token strings in Themes.swift (which stays a verbatim copy of the handoff).
extension AlmanacTheme {
    static let storageKey = "theme"
    static func named(_ id: String) -> AlmanacTheme { all.first { $0.id == id } ?? .nocturne }

    var name: String { ["ticker": "Ticker", "blocks": "Color Blocks", "nocturne": "Nocturne", "candy": "Candy Glass"][id] ?? id }
    var scheme: ColorScheme { id == "ticker" || id == "nocturne" ? .dark : .light }

    func c(_ key: String) -> Color { Color(css: tokens[key] ?? "#FF00FF") }
    func pt(_ key: String) -> CGFloat { CGFloat(Double((tokens[key] ?? "0").replacingOccurrences(of: "px", with: "")) ?? 0) }

    var label: Color { c("label") }
    var label2: Color { c("label2") }
    var label3: Color { c("label3") }
    var sep: Color { c("sep") }
    var sep2: Color { c("sep2") }
    var fill: Color { c("fill") }
    var fill2: Color { c("fill2") }
    var card: Color { c("card") }
    var cardBorder: Color { c("cardBorder") }
    var accent: Color { c("accent") }
    var accentText: Color { c("accentText") }
    var accentSoft: Color { c("accentSoft") }
    var onAccent: Color { c("onAccent") }
    var pos: Color { c("pos") }
    var neg: Color { c("neg") }
    var warn: Color { c("warn") }
    var glass: Color { c("glass") }
    var glassBorder: Color { c("glassBorder") }
    var segSel: Color { c("segSel") }
    var segText: Color { c("segText") }
    var navSel: Color { c("navSel") }
    var side: Color { c("side") }
    var sideBorder: Color { c("sideBorder") }
    var heroFg: Color { c("heroFg") }
    var heroFg2: Color { c("heroFg2") }
    var popover: Color { c("popover") }
    var field: Color { c("field") }
    var scrim: Color { c("scrim") }
    var sheet: Color { c("sheet") }
    var mapBase: Color { c("mapBase") }

    var r: CGFloat { pt("r") }
    var rS: CGFloat { pt("rS") }
    var heroPad: CGFloat { pt("heroPad") }
    var hasShadow: Bool { id == "candy" }
    var blurredCards: Bool { tokens["cardBlur"] != "none" }

    var design: Font.Design { id == "candy" ? .rounded : .default }
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: design) }
    private func weight(_ key: String) -> Font.Weight {
        switch tokens[key] { case "800": .heavy; case "700": .bold; case "600": .semibold; default: .regular }
    }
    var heroFont: Font { font(pt("hero"), weight("heroW")) }
    var heroTracking: CGFloat { pt("hero") * (Double(tokens["heroTrack"]?.replacingOccurrences(of: "em", with: "") ?? "0") ?? 0) }
    var numFont: Font { font(pt("num"), weight("numW")) }
    var numWeight: Font.Weight { weight("numW") }
    var titleFont: Font { font(pt("title"), weight("titleW")) }

    /// Hero container: a solid or gradient card (Color Blocks, Candy), or nothing.
    var heroBackground: AnyShapeStyle? {
        switch id {
        case "blocks": AnyShapeStyle(c("heroBg"))
        case "candy": AnyShapeStyle(LinearGradient(colors: [Color(css: "#6C5CFF"), Color(css: "#A44EF2"), Color(css: "#FF6EAE")], startPoint: .topLeading, endPoint: .bottomTrailing))
        default: nil
        }
    }

    // MARK: Sections and metrics

    enum Section: String { case insights, listing, reviews, appstore, sales, usage, territories }

    /// Sidebar icon square fill and glyph color.
    func square(_ s: Section) -> (bg: AnyShapeStyle, fg: Color) {
        switch id {
        case "nocturne":
            let m: [Section: String] = [.insights: "#FFB547", .listing: "#4DA3FF", .reviews: "#FF5FA2", .appstore: "#8B6CFF", .sales: "#3DD68C", .usage: "#FF8A3D", .territories: "#2FE0C8"]
            return (AnyShapeStyle(Color(css: m[s]!)), .white)
        case "blocks":
            let m: [Section: String] = [.insights: "#FF6A4D", .listing: "#7CC6FF", .reviews: "#C9F26B", .appstore: "#4433E0", .sales: "#141414", .usage: "#FFB020", .territories: "#2BB673"]
            return (AnyShapeStyle(Color(css: m[s]!)), [.listing, .reviews, .usage].contains(s) ? Color(css: "#111111") : .white)
        case "candy":
            let m: [Section: (String, String)] = [.insights: ("#FFC65C", "#FF8A3D"), .listing: ("#5AB8FF", "#4C7DFF"), .reviews: ("#FF8BC0", "#FF4F8B"), .appstore: ("#A88BFF", "#7B5CFF"), .sales: ("#5BE39B", "#1FB87A"), .usage: ("#FFA65C", "#FF6A3D"), .territories: ("#3FE3C0", "#1FB6C9")]
            return (Self.gradient(m[s]!), .white)
        default: return (AnyShapeStyle(fill), .white)
        }
    }

    /// Theme key for an App Store metric (imp, pv, ttr, dl, redl, conv), nil for the others.
    static func key(_ m: Metric) -> String? {
        switch m {
        case .impressions, .uniqueImpressions, .browseImpressions, .searchImpressions: "imp"
        case .pageViews: "pv"
        case .ttr: "ttr"
        case .firstDownloads, .downloads: "dl"
        case .redownloads: "redl"
        case .pageCR: "conv"
        default: nil
        }
    }

    /// Line / accent color for a metric. Ticker colors by direction instead (pass `up`).
    func color(_ m: Metric, up: Bool = true) -> Color {
        if colorByDirection { return up ? pos : neg }
        return Self.key(m).flatMap { metric[$0] }.map { Color(css: $0) } ?? accent
    }

    /// Icon square for a metric tile.
    func square(_ m: Metric) -> (bg: AnyShapeStyle, fg: Color) {
        let k = Self.key(m) ?? "dl"
        if usesRail { return (AnyShapeStyle(fill), .white) }
        if id == "candy" {
            let g: [String: (String, String)] = ["imp": ("#5AB8FF", "#4C7DFF"), "pv": ("#A88BFF", "#7B5CFF"), "ttr": ("#FF8BC0", "#FF4F8B"), "dl": ("#B98CFF", "#A44EF2"), "redl": ("#3FE3C0", "#1FB6C9"), "conv": ("#FFC65C", "#FF8A3D")]
            return (Self.gradient(g[k]!), .white)
        }
        return (AnyShapeStyle(Color(css: metric[k] ?? "#888888")), .white)
    }

    /// Color Blocks solid tiles: background, value color, secondary color.
    func tileFill(_ m: Metric) -> (bg: Color, fg: Color, fg2: Color)? {
        guard filledTiles, let k = Self.key(m) else { return nil }
        let f: [String: (String, String, String)] = [
            "imp": ("#FF6A4D", "#1F0E08", "rgba(31,14,8,0.72)"), "pv": ("#C9F26B", "#18200A", "rgba(24,32,10,0.7)"),
            "ttr": ("#141414", "#FFFFFF", "rgba(255,255,255,0.68)"), "redl": ("#7CC6FF", "#08243A", "rgba(8,36,58,0.72)"),
            "conv": ("#FFFFFF", "#111111", "#62626C"), "dl": ("#4433E0", "#FFFFFF", "rgba(255,255,255,0.8)"),
        ]
        return f[k].map { (Color(css: $0.0), Color(css: $0.1), Color(css: $0.2)) }
    }

    private static func gradient(_ p: (String, String)) -> AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [Color(css: p.0), Color(css: p.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

extension Color {
    /// `#RRGGBB`, `rgba(r,g,b,a)` or `transparent`.
    init(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), let v = UInt32(s.dropFirst(), radix: 16) {
            self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        } else if s.hasPrefix("rgba(") {
            let n = s.dropFirst(5).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            self.init(.sRGB, red: n[0] / 255, green: n[1] / 255, blue: n[2] / 255, opacity: n.count > 3 ? n[3] : 1)
        } else {
            self = .clear
        }
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = AlmanacTheme.nocturne }
extension EnvironmentValues {
    var theme: AlmanacTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Window background: flat color, Nocturne's two glows, or Candy's pastel wallpaper.
struct ThemeBackground: View {
    @Environment(\.theme) private var t
    var body: some View {
        switch t.id {
        case "candy":
            GeometryReader { g in
                ZStack {
                    Color(css: "#F6F4FA")
                    blob("#FFD8C8", at: UnitPoint(x: 0.08, y: 0), w: 0.6, h: 0.7, g)
                    blob("#D7D1FF", at: UnitPoint(x: 0.95, y: 0.05), w: 0.6, h: 0.7, g)
                    blob("#C6EEFF", at: UnitPoint(x: 0.55, y: 1.05), w: 0.7, h: 0.6, g)
                }
            }
        case "nocturne":
            ZStack(alignment: .topLeading) {
                t.c("bg")
                glow(Color(css: "#7A5CFF").opacity(0.34)).frame(width: 900, height: 660).offset(x: 180, y: -300)
                GeometryReader { g in
                    glow(Color(css: "#FF5FA2").opacity(0.14)).frame(width: 640, height: 560).offset(x: g.size.width - 400, y: 120)
                }
            }
            .clipped()
        default: t.c("bg")
        }
    }

    private func glow(_ c: Color) -> some View {
        Ellipse().fill(RadialGradient(colors: [c, c.opacity(0)], center: .center, startRadius: 0, endRadius: 330))
            .scaleEffect(x: 1.36, y: 1)
    }

    private func blob(_ hex: String, at p: UnitPoint, w: CGFloat, h: CGFloat, _ g: GeometryProxy) -> some View {
        let c = Color(css: hex)
        return EllipticalGradient(colors: [c, c.opacity(0)], center: p, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: g.size.width, height: g.size.height)
            .scaleEffect(x: w * 2, y: h * 2, anchor: p)
    }
}
