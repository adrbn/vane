import AlmanacCore
import SwiftUI

// Shared iPhone building blocks. Sizes follow the iOS handoff (IOS.md): 20 pt margins,
// card radius min(theme.r, 24), 34 pt large titles on root tabs, 28 pt on pushed screens.

extension AlmanacTheme {
    var phoneRadius: CGFloat { min(r, 24) }
    /// Hero number size on iPhone, per theme.
    var phoneHero: CGFloat { ["ticker": 56, "blocks": 64, "nocturne": 64, "candy": 56][id] ?? 56 }
    var phoneHeroFont: Font { font(phoneHero, id == "ticker" ? .bold : .heavy) }
}

extension View {
    /// Theme card with the iPhone radius.
    func phoneCard(padding: CGFloat = 16, fill: Color? = nil) -> some View {
        modifier(PhoneCardModifier(padding: padding, fill: fill))
    }
}

private struct PhoneCardModifier: ViewModifier {
    @Environment(\.theme) private var t
    var padding: CGFloat
    var fill: Color?
    func body(content: Content) -> some View { content.themedCard(padding: padding, fill: fill, radius: t.phoneRadius) }
}

/// Root tab screen: app picker row, 34 pt title, 14 pt subtitle, then scrolling content.
struct PhoneScreen<Trailing: View, Content: View>: View {
    @Environment(\.theme) private var t
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { AppPicker(); Spacer(); trailing }
                    .frame(height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(t.font(34, .heavy)).tracking(-0.6)
                    Text(subtitle).font(t.font(14)).foregroundStyle(t.label2)
                }
                .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(t.label)
        .background(ThemeBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension PhoneScreen where Trailing == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// Pushed screen (Metric detail, Territories, Report, Settings): system glass back button, 28 pt title.
struct PushedScreen<Content: View>: View {
    @Environment(\.theme) private var t
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(t.font(28, .heavy)).tracking(-0.4)
                    if !subtitle.isEmpty { Text(subtitle).font(t.font(13)).foregroundStyle(t.label2) }
                }
                .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(t.label)
        .background(ThemeBackground().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// App switcher pill: icon, name, chevron.
struct AppPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var body: some View {
        Menu {
            ForEach(model.apps) { a in
                Button { model.appId = a.id } label: {
                    if a.id == model.appId { Label(a.name, systemImage: "checkmark") } else { Text(a.name) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let app = model.app { AppIconView(app: app, size: 26) }
                Text(model.app?.name ?? "No app").font(t.font(14, .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(t.label2)
            }
            .foregroundStyle(t.label)
            .padding(.leading, 6).padding(.trailing, 12).frame(height: 38)
            .background(t.glass, in: Capsule())
            .overlay(Capsule().strokeBorder(t.glassBorder, lineWidth: 1))
        }
    }
}

/// 38 pt round glass button for the nav row.
struct PhoneIconButton: View {
    @Environment(\.theme) private var t
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.label)
                .frame(width: 38, height: 38)
                .background(t.glass, in: Circle())
                .overlay(Circle().strokeBorder(t.glassBorder, lineWidth: 1))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Hero card: the theme's filled block (Color Blocks, Candy) or plain number (Ticker, Nocturne).
struct PhoneHero: View {
    @Environment(\.theme) private var t
    var label: String
    var value: String
    var caption: Text
    var spark: [Double] = []

    var body: some View {
        let filled = t.heroBackground != nil
        let fg = filled ? t.heroFg : t.label, fg2 = filled ? t.heroFg2 : t.label2
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(t.font(13, .semibold)).foregroundStyle(fg2)
            Text(value).font(t.phoneHeroFont).tracking(t.phoneHero * -0.04).foregroundStyle(fg)
                .lineLimit(1).minimumScaleFactor(0.5)
            caption.font(t.font(13)).foregroundStyle(fg2)
            if spark.count > 1 {
                Spark(values: spark, color: filled ? fg.opacity(0.85) : t.accent, width: 1.5).frame(height: 28).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(filled ? 20 : 4)
        .background {
            if let bg = t.heroBackground { RoundedRectangle(cornerRadius: t.phoneRadius, style: .continuous).fill(bg) }
        }
    }
}

/// 2-column metric tile. Color Blocks fills it with the metric's color.
struct PhoneTile: View {
    @Environment(\.theme) private var t
    var metric: Metric?
    var label: String
    var value: String
    var change: Change?
    var note: String? = nil
    var spark: [Double] = []

    var body: some View {
        let fill = metric.flatMap { t.tileFill($0) }
        let fg = fill?.fg ?? t.label, fg2 = fill?.fg2 ?? t.label2
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(t.font(12, .semibold)).foregroundStyle(fg2).lineLimit(1)
            Text(value).font(t.font(28, t.numWeight)).tracking(-0.6).foregroundStyle(fg)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let change {
                Text(change.text).font(t.font(11, .semibold))
                    .foregroundStyle(fill != nil ? fg : change.color(t))
            } else if let note {
                Text(note).font(t.font(11, .semibold)).foregroundStyle(fg2).lineLimit(1)
            }
            if spark.count > 1 {
                Spark(values: spark, color: fill != nil ? fg.opacity(0.8) : (metric.map { t.color($0, up: change?.up ?? true) } ?? t.accent), width: 1.5)
                    .frame(height: 20).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .phoneCard(padding: 14, fill: fill?.bg)
    }
}

/// Section label above a group ("New · 3 insights").
struct PhoneSectionTitle: View {
    @Environment(\.theme) private var t
    var title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(t.font(17, .bold))
            if !detail.isEmpty { Text(detail).font(t.font(13)).foregroundStyle(t.label2) }
        }
        .padding(.top, 8)
    }
}

/// Full-width capsule button (54 high) for primary actions.
struct PhoneButton: View {
    @Environment(\.theme) private var t
    var label: String
    var prominent = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(t.font(17, .semibold))
                .foregroundStyle(prominent ? t.onAccent : t.label)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(prominent ? t.accent : t.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Segmented control in the theme's style, full width.
struct PhoneSegments<V: Hashable>: View {
    @Environment(\.theme) private var t
    var options: [(V, String)]
    @Binding var selection: V
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (v, label) = options[i]
                let on = v == selection
                Button { withAnimation(.snappy) { selection = v } } label: {
                    Text(label).font(t.font(14, .semibold)).lineLimit(1)
                        .foregroundStyle(on ? t.segText : t.label2)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(on ? t.segSel : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(t.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(t.glassBorder, lineWidth: 1))
    }
}
