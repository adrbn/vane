import AlmanacCore
#if os(macOS)
import AppKit
#endif
import SwiftUI

#if os(macOS)
/// Weekly / Monthly / Yearly report: its own window, no sidebar. Only complete periods are shown.
struct ReportView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.blocks.id
    @State var ref: ReportRef
    @State private var section = "Summary"

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        let report = ReportBuilder(store: model.store, app: ref.appId).build(ref.period, start: ref.start)
        let span = dataSpan
        ZStack {
            ThemeBackground()
            VStack(spacing: 0) {
                header(report, span)
                ScrollViewReader { proxy in
                    ScrollView {
                        ReportBody(report: report, span: span, section: $section) { id in
                            section = id
                            withAnimation { proxy.scrollTo(id, anchor: .top) }
                        }
                        .frame(maxWidth: 880).frame(maxWidth: .infinity)
                        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 24)
                    }
                    .scrollIndicators(.never)
                    .clipped()
                }
            }
        }
        .background(WindowChrome())
        .ignoresSafeArea()
        .foregroundStyle(t.label)
        .font(t.font(13))
        .tint(t.accent)
        .environment(\.theme, t)
        .preferredColorScheme(t.scheme)
        .onAppear { ref = complete(ref) }
    }

    private func header(_ r: Report, _ span: ClosedRange<String>?) -> some View {
        let t = AlmanacTheme.named(themeId)
        let next = shifted(ref, 1)
        // Title block sits under the traffic lights, on the same centered 880 pt column as the body.
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text.tracked("\(r.period.title) Report", -0.2).font(t.titleFont).lineLimit(1).frame(height: 26)
                Text("\(r.appName) · \(r.periodLabel)").font(t.font(12)).foregroundStyle(t.label2).lineLimit(1)
            }
            Spacer(minLength: 12)
            GlassSegments(options: ReportPeriod.allCases.map { ($0, $0.title) }, selection: Binding(
                get: { ref.period },
                set: { p in ref = complete(ReportRef(appId: ref.appId, period: p, start: Self.start(p, ref.start))); section = "Summary" }))
            GlassGroup {
                chevron("chevron.left", help: "Previous", enabled: span.map { ref.start > $0.lowerBound } ?? false) { ref = shifted(ref, -1) }
                chevron("chevron.right", help: "Next", enabled: span.map { end(next) <= $0.upperBound } ?? false) { ref = next }
            }
            GlassGroup {
                ShareLink(item: r.plainText, subject: Text("\(r.appName) \(r.period.title.lowercased()) report, \(r.periodLabel)")) {
                    Label("Share", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
                        .font(t.font(13, .semibold)).foregroundStyle(t.label)
                        .padding(.horizontal, 12).frame(height: 28).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                GlassItem(label: "Export PDF") { exportPDF(r, span, t) }
            }
            .fixedSize()
        }
        .frame(maxWidth: 880).frame(maxWidth: .infinity)
        .padding(.top, 44).padding(.horizontal, 24)
        .frame(height: 88, alignment: .top)
    }

    private func chevron(_ symbol: String, help: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        let t = AlmanacTheme.named(themeId)
        return Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(enabled ? t.label : t.label3)
                .frame(width: 32, height: 28).contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled).help(help)
    }

    // MARK: Periods

    /// First and last day with sales or analytics for this app.
    private var dataSpan: ClosedRange<String>? {
        guard let last = model.store.lastDay(ref.appId),
              let first = model.store.series(ref.appId, .downloads, from: "2000-01-01", to: last).first?.day, first <= last else { return nil }
        return first...last
    }

    private func end(_ r: ReportRef) -> String { ReportBuilder(store: model.store, app: r.appId).build(r.period, start: r.start).end }

    private func shifted(_ r: ReportRef, _ dir: Int) -> ReportRef {
        let c: Calendar.Component = r.period == .week ? .weekOfYear : r.period == .month ? .month : .year
        let d = Day.calendar.date(byAdding: c, value: dir, to: Day.date(r.start))!
        return ReportRef(appId: r.appId, period: r.period, start: Day.string(d))
    }

    /// Steps back until the whole period is covered by data, so a report never compares half a week.
    private func complete(_ r: ReportRef) -> ReportRef {
        guard let last = model.store.lastDay(r.appId) else { return r }
        var r = r
        for _ in 0..<3 where end(r) > last { r = shifted(r, -1) }
        return r
    }

    static func start(_ p: ReportPeriod, _ day: String) -> String {
        switch p {
        case .week: Day.weekStart(day)
        case .month: Day.monthStart(day)
        case .year: Day.yearStart(day)
        }
    }

    // MARK: PDF

    private func exportPDF(_ r: Report, _ span: ClosedRange<String>?, _ t: AlmanacTheme) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(r.appName) \(r.period.title) Report \(r.start).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let page = ReportBody(report: r, span: span, section: .constant(""), printable: true) { _ in }
            .frame(width: 720).padding(40)
            .background(t.c("bg"))
            .foregroundStyle(t.label).font(t.font(13)).tint(t.accent)
            .environment(\.theme, t).environment(\.colorScheme, t.scheme)
        let renderer = ImageRenderer(content: page)
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF()
        }
    }
}
#endif

/// KPI row, table of contents and reading column. Shared by the window and the PDF export.
struct ReportBody: View {
    @Environment(\.theme) private var t
    let report: Report
    let span: ClosedRange<String>?
    @Binding var section: String
    var printable = false
    let jump: (String) -> Void

    var body: some View {
        let ids = ["Summary"] + report.sections.map(\.heading)
        VStack(alignment: .leading, spacing: 32) {
            if printable {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(report.appName) · \(report.period.title) Report").font(t.font(22, .bold))
                    Text(report.periodLabel).font(t.font(13)).foregroundStyle(t.label2)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(report.headline) { kpi($0).frame(maxWidth: 220) }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 40) {
                if !printable {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(ids, id: \.self) { id in
                                let on = id == section
                                Button { jump(id) } label: {
                                    Text(id).font(t.font(13, on ? .semibold : .regular)).foregroundStyle(on ? t.label : t.label2).lineLimit(2)
                                        .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 28).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(on ? t.accentSoft : .clear, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text(caption).font(t.font(11)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10)
                    }
                    .frame(width: 176)
                }
                VStack(alignment: .leading, spacing: 32) {
                    block("Summary", [report.summary])
                    ForEach(Array(report.sections.enumerated()), id: \.offset) { i, s in
                        VStack(alignment: .leading, spacing: 16) {
                            block(s.heading, s.paragraphs)
                            if i == 0, let first = report.headline.first, first.spark.contains(where: { $0.value > 0 }) {
                                bars(first.spark, year: report.period == .year)
                            }
                        }
                    }
                    if printable { Text(caption).font(t.font(11)).foregroundStyle(t.label2) }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .textSelection(.enabled)
            }
        }
    }

    private var caption: String {
        let through = span.map { " Figures through \(Day.date($0.upperBound).formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US"))))." } ?? ""
        return "Written on this Mac from your App Store Connect data.\(through)"
    }

    private func block(_ heading: String, _ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(t.font(20, .bold))
            ForEach(paragraphs, id: \.self) {
                Text($0).font(t.font(15)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(heading)
    }

    private func kpi(_ k: Report.KPI) -> some View {
        let fill = t.tileFill(k.metric == .proceeds ? .redownloads : k.metric)
        let c = Change(k.metric, value: k.value, previous: k.previous, arrows: false)
        let vs = c.text == "No earlier data" ? "" : " vs last \(report.period.rawValue)"
        return VStack(alignment: .leading, spacing: 6) {
            Text(MetricCard.label(k.metric)).font(t.font(12, .semibold)).foregroundStyle(fill?.fg2 ?? t.label2).lineLimit(1)
            Text.tracked(Num.value(k.metric, k.value), -0.8).font(t.font(30, t.numWeight)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(c.text + vs).font(t.font(11, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(fill?.fg ?? c.color(t))
        }
        .foregroundStyle(fill?.fg ?? t.label)
        .themedCard(padding: 16, fill: fill?.bg)
    }

    /// Daily bars for a week or month, monthly bars for a year. Peak in accent.
    private func bars(_ points: [Point], year: Bool) -> some View {
        let peak = points.map(\.value).max() ?? 1
        let few = points.count <= 12
        let en = Locale(identifier: "en_US")
        return HStack(alignment: .bottom, spacing: few ? 8 : 3) {
            ForEach(points) { p in
                VStack(spacing: 4) {
                    if few { Text(Num.k(p.value)).font(t.font(10, .semibold)).foregroundStyle(t.label2).monospacedDigit() }
                    RoundedRectangle(cornerRadius: few ? 4 : 2, style: .continuous)
                        .fill(p.value == peak ? t.accent : t.accent.opacity(0.35))
                        .frame(height: max(3, 96 * p.value / max(peak, 1)))
                    Text(year ? p.date.formatted(.dateTime.month(.abbreviated).locale(en))
                         : few ? p.date.formatted(.dateTime.weekday(.abbreviated).locale(en))
                         : (Int(p.day.suffix(2)) ?? 0) % 5 == 1 ? String(Int(p.day.suffix(2)) ?? 0) : " ")
                        .font(t.font(10)).foregroundStyle(t.label2).lineLimit(1).fixedSize()
                }
                .frame(maxWidth: .infinity)
                .help("\(p.date.formatted(.dateTime.month(.abbreviated).day().locale(en))): \(Num.int(p.value))")
            }
        }
        .frame(height: 140, alignment: .bottom)
    }
}
