import AlmanacCore
import SwiftUI

/// Shown on App Store until the first analytics report exists: what happened, what's next, when. No skeletons.
struct DataArrivingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        let app = model.appId ?? ""
        // Days covered by the sales reports, read from what was actually stored.
        let salesDays = model.store.lastDay(app, .firstDownloads).map { last in model.store.series(app, .firstDownloads, from: "2000-01-01", to: last).map(\.day) } ?? []
        Screen(title: String(localized: "App Store"), subtitle: String(localized: "\(model.app?.name ?? "") · Waiting for Apple"), inspector: false) {} content: {
            VStack(alignment: .leading, spacing: 24) {
                status(salesDays)
                if model.needsAdmin { AdminRequestCard() }
                section(String(localized: "Available now"), String(localized: "Sales reports go back a year, so these were imported right away")) { sales(app) }
                section(String(localized: "Waiting for Apple"), String(localized: "Each metric fills in with the first analytics report")) { pending }
            }
        }
    }

    private func status(_ salesDays: [String]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: "clock").font(.system(size: 22, weight: .semibold)).foregroundStyle(t.accentText)
                    .frame(width: 52, height: 52).background(t.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text.tracked(String(localized: "Your first App Store report arrives in 24–48 hours"), -0.26).font(t.font(26, .bold))
                    (model.needsAdmin
                        ? Text("Sales history is here. Apple’s analytics start one to two days after the one-time step below.")
                        : Text("Apple publishes App Store analytics one to two days after each day ends. Vane requested the report for \(model.app?.name ?? String(localized: "this app")), checks for it in the background and notifies you when it lands."))
                        .font(t.font(14)).foregroundStyle(t.label2).frame(maxWidth: 620, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SmallButton(label: model.syncing ? String(localized: "Checking…") : String(localized: "Check Now"), busy: model.syncing) { Task { await model.refresh() } }
            }
            HStack(alignment: .top, spacing: 16) {
                step(String(localized: "Key verified"), model.lastSync.map { String(localized: "Last refresh \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "Connected"), .done)
                step(String(localized: "Sales history imported"), salesDays.isEmpty ? String(localized: "Nothing yet") : String(localized: "\(salesDays.count) days, \(AppStoreData.md(salesDays.first!)) – \(AppStoreData.md(salesDays.last!))"), salesDays.isEmpty ? .wait : .done)
                if model.needsAdmin {
                    step(String(localized: "Analytics report"), String(localized: "Needs an Admin key once"), .todo)
                } else {
                    step(String(localized: "Analytics report requested"), String(localized: "Apple is preparing it"), .wait)
                }
                step(String(localized: "First insights"), String(localized: "After 7 days of analytics"), .todo)
            }
            .padding(.leading, 72)
        }
        .themedCard(padding: 28)
    }

    private enum StepState { case done, wait, todo }

    private func step(_ title: String, _ sub: String, _ s: StepState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().strokeBorder(s == .todo ? t.label3 : t.accent, lineWidth: 1.5)
                    .background(Circle().fill(s == .done ? t.accent : .clear))
                if s == .done { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(t.onAccent) }
                if s == .wait { Image(systemName: "clock").font(.system(size: 10, weight: .bold)).foregroundStyle(t.accent) }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(t.font(13, .bold)).foregroundStyle(s == .todo ? t.label2 : t.label).frame(height: 20)
                Text(sub).font(t.font(12)).foregroundStyle(t.label2).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<C: View>(_ title: String, _ sub: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(t.font(15, .bold))
                Text(sub).font(t.font(13)).foregroundStyle(t.label2).lineLimit(1)
            }
            content()
        }
    }

    private func sales(_ app: String) -> some View {
        let to = model.store.lastDay(app, .firstDownloads) ?? Day.today()
        let from = Day.add(-27, to: to), pTo = Day.add(-1, to: from), pFrom = Day.add(-27, to: pTo)
        let spark = model.store.series(app, .firstDownloads, from: from, to: to).map(\.value)
        // Compare only when the previous 28 days are fully covered, never against the launch weeks.
        let full = model.store.series(app, .firstDownloads, from: "2000-01-01", to: to).first.map { $0.day <= pFrom } ?? false
        return HStack(spacing: 32) {
            kpi(String(localized: "First-time downloads, last 28 days"), .firstDownloads, app, from, to, pFrom, pTo, full)
            kpi(String(localized: "Redownloads"), .redownloads, app, from, to, pFrom, pTo, full)
            kpi(String(localized: "Proceeds"), .proceeds, app, from, to, pFrom, pTo, full)
            ZStack {
                LinePath(values: spark, floorZero: true, closed: true).fill(t.accent.opacity(0.1))
                Spark(values: spark, color: t.accent)
            }
            .frame(height: 56)
            SmallButton(label: String(localized: "Open Sales")) { model.section = .sales }
        }
        .themedCard(padding: 20)
    }

    private func kpi(_ label: String, _ m: Metric, _ app: String, _ from: String, _ to: String, _ pf: String, _ pt: String, _ full: Bool) -> some View {
        let v = model.store.total(app, m, from: from, to: to), p = model.store.total(app, m, from: pf, to: pt)
        let c = full ? Change(m, value: v, previous: p) : Change.noHistory
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(t.font(13)).foregroundStyle(t.label2)
            Text.tracked(m == .proceeds ? m.format(v) : Num.int(v), -0.6).font(t.numFont).monospacedDigit()
            (Text(c.text).foregroundStyle(c.color(t)).fontWeight(.bold) + Text(c.text == Change.noHistory.text ? "" : String(localized: " vs \(m == .proceeds ? m.format(p) : Num.int(p))")).foregroundStyle(t.label2))
                .font(t.font(13)).monospacedDigit()
        }
        .fixedSize()
    }

    private var pending: some View {
        // Downloads already come from the sales reports; only the funnel needs Apple's analytics report.
        let items: [Metric] = [.impressions, .pageViews, .ttr, .pageCR]
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2) { r in
                GridRow {
                    ForEach(0..<2) { c in
                        let m = items[r * 2 + c]
                        HStack(spacing: 12) {
                            IconSquare(symbol: MetricCard.symbol(m), style: t.square(m), size: 28).opacity(0.55)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(MetricCard.label(m)).font(t.font(14, .semibold)).lineLimit(1)
                                Text("Expected in 24–48 hours").font(t.font(12)).foregroundStyle(t.label2)
                            }
                            Spacer(minLength: 8)
                            Text("—").font(t.font(20, .semibold)).foregroundStyle(t.label3)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .overlay(alignment: .leading) { if c > 0 { t.sep.frame(width: 1) } }
                        .overlay(alignment: .top) { if r > 0 { t.sep.frame(height: 1) } }
                    }
                }
            }
        }
        .themedCard(padding: 0)
    }
}

/// Apple's analytics report hasn't landed: says when, what's done, and offers a check. Sits inside the real layout.
struct AnalyticsPending: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let compact: Bool
    static let expected = String(localized: "Expected in 24–48 hours")

    var body: some View {
        if model.needsAdmin { AdminRequestCard(fill: !compact) } else { waiting }
    }

    @ViewBuilder private var waiting: some View {
        // Apple publishes each analytics report on its own schedule: sessions often land days before impressions.
        let sessions = model.store.series(model.appId ?? "", .sessions).first?.day
        let title = Text(sessions == nil ? String(localized: "App Store analytics arrive in 24–48 hours") : String(localized: "Impressions and conversion are still on their way")).font(t.font(compact ? 15 : 17, .bold))
        let sub = Text(sessions == nil
            ? String(localized: "Downloads come from your sales reports. Impressions, conversion, sessions and crashes fill in with Apple’s first analytics report.")
            : String(localized: "Apple’s sessions report has arrived and is in Usage. Its App Store engagement report, which holds impressions and page views, usually follows within a few days."))
            .font(t.font(13)).foregroundStyle(t.label2)
        let check = SmallButton(label: model.syncing ? String(localized: "Checking…") : String(localized: "Check Now"), busy: model.syncing) { Task { await model.refresh() } }
        let icon = Image(systemName: "clock").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.accentText)
            .frame(width: 36, height: 36).background(t.accentSoft, in: RoundedRectangle(cornerRadius: t.inner(14), style: .continuous))
        if compact {
            HStack(spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 2) { title; sub.lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                Spacer(minLength: 12)
                check
            }
            .themedCard(padding: 14)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    icon
                    VStack(alignment: .leading, spacing: 4) { title; sub.fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 12)
                    check
                }
                Spacer(minLength: 16)
                HStack(spacing: 16) {
                    step(String(localized: "Sales history imported"), true)
                    if sessions == nil { step(String(localized: "Analytics report requested"), true) }
                    step(sessions.map { String(localized: "Sessions since \(AppStoreData.md($0))") } ?? String(localized: "First analytics report"), sessions != nil)
                    if sessions != nil { step(String(localized: "Impressions report"), false) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
        }
    }

    private func step(_ s: String, _ done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "clock").font(.system(size: 14, weight: .semibold)).foregroundStyle(done ? t.accent : t.label2)
            Text(s).font(t.font(13, .semibold)).foregroundStyle(done ? t.label : t.label2).lineLimit(1)
        }
    }
}
