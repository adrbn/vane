import AlmanacCore
import SwiftUI

// MARK: - Screen scaffold: 72 pt header (title + subtitle + glass groups), then content.

struct Screen<Controls: View, Content: View>: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model
    var title: String
    var subtitle: String
    var inspector = false
    var scrolls = true
    /// false: the content brings its own padding (Sales and Usage, kept from the previous design).
    var padded = true
    @ViewBuilder var controls: Controls
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            // One row when it fits; otherwise the controls drop to a second row instead of truncating the title.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    heading.fixedSize()
                    Spacer(minLength: 12)
                    controls.fixedSize()
                    ask
                }
                .padding(.top, 20).padding(.leading, 28).padding(.trailing, 20)
                .frame(height: 80)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) { heading; Spacer(minLength: 12); ask }
                    HStack(spacing: 8) { controls }.fixedSize()
                }
                .padding(.top, 20).padding(.leading, 28).padding(.trailing, 20).padding(.bottom, 4)
            }
            Group {
                if scrolls {
                    ScrollView { content.padding(.top, 12).padding(.leading, 28).padding([.trailing, .bottom], 24) }
                        .scrollIndicators(.never)
                } else if padded {
                    content.padding(.top, 12).padding(.leading, 28).padding([.trailing, .bottom], 24)
                } else {
                    content.padding(.leading, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension Screen {
    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(t.titleFont).tracking(-0.2).lineLimit(1).frame(height: 26)
            Text(subtitle).font(t.font(12)).foregroundStyle(t.label2).lineLimit(1)
        }
    }

    @ViewBuilder private var ask: some View {
        if inspector {
            GlassIconButton(symbol: "sparkles", on: model.chatOpen, help: "Ask about this screen") { model.chatOpen.toggle() }
        }
    }
}

// MARK: - Glass groups (toolbar controls)

struct GlassGroup<Content: View>: View {
    @Environment(\.theme) private var t
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 2) { content }
            .padding(.horizontal, 3)
            .frame(height: 34)
            .background(t.glass, in: Capsule())
            .overlay(Capsule().strokeBorder(t.glassBorder, lineWidth: 1))
    }
}

/// Segmented control drawn as a glass group: selected item is `segSel` / `segText`.
struct GlassSegments<V: Hashable>: View {
    @Environment(\.theme) private var t
    var options: [(V, String)]
    @Binding var selection: V
    var body: some View {
        GlassGroup {
            ForEach(options.indices, id: \.self) { i in
                let (v, label) = options[i]
                let on = v == selection
                Button { selection = v } label: {
                    Text(label).font(t.font(13, .semibold)).lineLimit(1)
                        .padding(.horizontal, 12).frame(height: 28)
                        .foregroundStyle(on ? t.segText : t.label2)
                        .background(on ? t.segSel : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A plain item inside a GlassGroup (menu-looking or action).
struct GlassItem: View {
    @Environment(\.theme) private var t
    var label: String
    var symbol: String? = nil
    var chevron = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(label).lineLimit(1)
                if chevron { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label2) }
            }
            .font(t.font(13, .semibold)).foregroundStyle(t.label)
            .padding(.horizontal, 12).frame(height: 28).contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct GlassIconButton: View {
    @Environment(\.theme) private var t
    var symbol: String
    var on = false
    var help = ""
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? t.segText : t.label)
                .frame(width: 34, height: 34)
                .background(on ? t.segSel : t.glass, in: Circle())
                .overlay(Circle().strokeBorder(t.glassBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Cards

struct ThemedCard: ViewModifier {
    @Environment(\.theme) private var t
    var padding: CGFloat = 20
    var fill: Color?
    var highlighted = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: t.r, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                if fill == nil && t.blurredCards { shape.fill(.ultraThinMaterial).opacity(t.scheme == .dark ? 0.0 : 0.6) }
            }
            .background(fill ?? t.card, in: shape)
            .overlay(shape.strokeBorder(highlighted ? t.accent : fill == nil ? t.cardBorder : .clear, lineWidth: 1))
            .shadow(color: t.hasShadow ? Color(css: "rgba(80,60,140,0.07)") : .clear, radius: 12, y: 8)
    }
}

extension View {
    func themedCard(padding: CGFloat = 20, fill: Color? = nil, highlighted: Bool = false) -> some View {
        modifier(ThemedCard(padding: padding, fill: fill, highlighted: highlighted))
    }
    /// Makes a whole tile a link to its screen: click anywhere (inner buttons keep their own action), pointing-hand cursor.
    @ViewBuilder func opens(_ action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) { contentShape(Rectangle()) }
                .buttonStyle(.plain)
                #if os(macOS)
                .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                #endif
        } else { self }
    }
}

/// Rounded square holding a white glyph (sidebar sections, metric tiles).
struct IconSquare: View {
    var symbol: String
    var style: (bg: AnyShapeStyle, fg: Color)
    var size: CGFloat = 24
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(style.fg)
            .frame(width: size, height: size)
            .background(style.bg, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct SmallButton: View {
    @Environment(\.theme) private var t
    var label: String
    var symbol: String? = nil
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(label).lineLimit(1)
            }
            .font(t.font(13, .semibold))
            .foregroundStyle(prominent ? t.onAccent : t.label)
            .padding(.horizontal, 12).frame(height: 28)
            .background(prominent ? t.accent : t.fill, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Changes: % for counts, points for rates, "No change" under 0.05 pts.

struct Change {
    var text: String
    var up: Bool
    var flat: Bool

    init(_ metric: Metric, value: Double, previous: Double, arrows: Bool = true) {
        if metric.isRate {
            let pts = (value - previous) * 100
            up = pts >= 0; flat = abs(pts) < 0.05
            text = flat ? "No change" : "\(arrows ? (up ? "↑ " : "↓ ") : (up ? "+" : "−"))\(String(format: "%.1f", abs(pts))) pts"
        } else if previous > 0 {
            let r = value / previous - 1
            up = r >= 0; flat = abs(r) < 0.0005
            text = flat ? "No change" : "\(arrows ? (up ? "↑ " : "↓ ") : (up ? "+" : "−"))\(String(format: "%.1f", abs(r) * 100))%"
        } else {
            up = true; flat = true; text = "No earlier data"
        }
    }

    /// The earlier period isn't fully covered by history: say so instead of a misleading percentage.
    static let noHistory: Change = {
        var c = Change(.downloads, value: 0, previous: 0)
        c.text = "No earlier data"
        return c
    }()

    /// Down is good for crashes.
    func color(_ t: AlmanacTheme, invert: Bool = false) -> Color { flat ? t.label2 : (up != invert) ? t.pos : t.neg }
}

// MARK: - Compact number formatting used across the redesign (5,412 · 48.2K · 1.3M).

enum Num {
    static func int(_ v: Double) -> String { Int(v.rounded()).formatted(.number.locale(Locale(identifier: "en_US"))) }
    static func k(_ v: Double) -> String {
        if v >= 1e6 { return String(format: "%.1fM", v / 1e6) }
        if v >= 1e4 { return String(format: "%.1fK", v / 1e3) }
        return int(v)
    }
    static func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    static func value(_ m: Metric, _ v: Double) -> String {
        m.isRate ? pct(v) : (m == .proceeds || m == .sales) ? m.format(v) : k(v)
    }
}

// MARK: - Sparkline as a plain path (no axes, stretches to fill).

struct LinePath: Shape {
    var values: [Double]
    var floorZero = false
    var closed = false
    func path(in r: CGRect) -> Path {
        guard values.count > 1, let lo0 = values.min(), let hi = values.max() else { return Path() }
        let lo = floorZero ? 0 : lo0 - (hi - lo0) * 0.15
        let top = floorZero ? hi * 1.12 : hi + (hi - lo0) * 0.15
        let span = max(top - lo, 1e-9)
        let pts = values.enumerated().map { i, v in
            CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1), y: r.minY + r.height * (1 - CGFloat((v - lo) / span)))
        }
        var p = Path()
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.addLine(to: $0) }
        if closed { p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath() }
        return p
    }
}

struct Spark: View {
    var values: [Double]
    var color: Color
    var width: CGFloat = 2
    var body: some View {
        LinePath(values: values).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Centered sheet over the blurred screen.

struct CenteredSheet<Content: View>: View {
    @Environment(\.theme) private var t
    var width: CGFloat = 600
    var onDismiss: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            // The screen behind is blurred by its owner; no tint, so dark themes don't go darker.
            Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            content
                .padding(24)
                .frame(width: width)
                .background(t.sheet, in: RoundedRectangle(cornerRadius: t.r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: t.r, style: .continuous).strokeBorder(t.cardBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 30, y: 16)
                .padding(.vertical, 40)
        }
        #if os(macOS)
        .onExitCommand(perform: onDismiss)
        #endif
    }
}

/// "—" in label3 with the date a value is expected (no skeletons).
struct Pending: View {
    @Environment(\.theme) private var t
    var expected: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("—").font(t.numFont).foregroundStyle(t.label3)
            Text(expected).font(t.font(12)).foregroundStyle(t.label2)
        }
    }
}
