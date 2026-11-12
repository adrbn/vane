import AlmanacCore
import SwiftUI

/// Shown on App Store until the first analytics report exists: what happened, what's next, when. No skeletons.
struct DataArrivingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        let app = model.appId ?? ""
        let salesDays = (model.store.meta("sales_days") ?? "").split(separator: ",").map(String.init).sorted()
        Screen(title: "App Store", subtitle: "\(model.app?.name ?? "") · Waiting for Apple", inspector: false) {} content: {
            VStack(alignment: .leading, spacing: 24) {
                status(salesDays)
                section("Available now", "Sales reports go back a year, so these were imported right away") { sales(app) }
                section("Waiting for Apple", "Each metric fills in with the first analytics report") { pending }
            }
        }
    }

    private func status(_ salesDays: [String]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: "clock").font(.system(size: 22, weight: .semibold)).foregroundStyle(t.accentText)
                    .frame(width: 52, height: 52).background(t.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your first App Store report arrives in 24–48 hours").font(t.font(26, .bold)).tracking(-0.26)
                    Text("Apple publishes App Store analytics one to two days after each day ends. Almanac requested the report for \(model.app?.name ?? "this app"), checks for it in the background and notifies you when it lands.")
                        .font(t.font(14)).foregroundStyle(t.label2).frame(maxWidth: 620, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SmallButton(label: model.syncing ? "Checking…" : "Check Now") { Task { await model.refresh() } }.disabled(model.syncing)
            }
            HStack(alignment: .top, spacing: 16) {
                step("Key verified", model.lastSync.map { "Last refresh \($0.formatted(.relative(presentation: .named)))" } ?? "Connected", .done)
                step("Sales history imported", salesDays.isEmpty ? "Nothing yet" : "\(salesDays.count) days, \(AppStoreData.md(salesDays.first!)) – \(AppStoreData.md(salesDays.last!))", salesDays.isEmpty ? .wait : .done)
                step("Analytics report requested", "Apple is preparing it", .wait)
                step("First insights", "After 7 days of analytics", .todo)
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
        let to = model.store.lastDay(app, .sales) ?? Day.today()
        let from = Day.add(-27, to: to), pTo = Day.add(-1, to: from), pFrom = Day.add(-27, to: pTo)
        let spark = model.store.series(app, .sales, from: from, to: to).map(\.value)
        return HStack(spacing: 32) {
            kpi("Units, last 28 days", .sales, app, from, to, pFrom, pTo)
            kpi("Proceeds, last 28 days", .proceeds, app, from, to, pFrom, pTo)
            ZStack {
                LinePath(values: spark, floorZero: true, closed: true).fill(t.accent.opacity(0.1))
                Spark(values: spark, color: t.accent)
            }
            .frame(height: 56)
            SmallButton(label: "Open Sales") { model.section = .sales }
        }
        .themedCard(padding: 20)
    }

    private func kpi(_ label: String, _ m: Metric, _ app: String, _ from: String, _ to: String, _ pf: String, _ pt: String) -> some View {
        let v = model.store.total(app, m, from: from, to: to), p = model.store.total(app, m, from: pf, to: pt)
        let c = Change(m, value: v, previous: p)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(t.font(13)).foregroundStyle(t.label2)
            Text(m == .proceeds ? m.format(v) : Num.int(v)).font(t.numFont).tracking(-0.6).monospacedDigit()
            (Text(c.text).foregroundStyle(c.color(t)).fontWeight(.bold) + Text(" was \(m == .proceeds ? m.format(p) : Num.int(p))").foregroundStyle(t.label2))
                .font(t.font(13)).monospacedDigit()
        }
        .fixedSize()
    }

    private var pending: some View {
        let items: [Metric] = [.impressions, .pageViews, .ttr, .firstDownloads, .redownloads, .pageCR]
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2) { r in
                GridRow {
                    ForEach(0..<3) { c in
                        let m = items[r * 3 + c]
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
