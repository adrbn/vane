import AlmanacCore
import SwiftUI

struct ReportView: View {
    @Environment(AppModel.self) private var model
    @State var ref: ReportRef
    @State private var aiText: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let report = ReportBuilder(store: model.store, app: ref.appId).build(ref.period, start: ref.start)
        let app = model.apps.first { $0.id == ref.appId }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(report, app)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(report.kpis) { kpiCard($0, tint: app?.tint ?? .accentColor) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary").font(.title3.weight(.semibold))
                    Text(report.summary)
                    if let aiText {
                        Text(aiText).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8)).textSelection(.enabled)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                ForEach(report.sections) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.heading).font(.title3.weight(.semibold))
                        ForEach(s.paragraphs, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("\(report.appName) — \(report.period.title) report — \(report.periodLabel)")
        .toolbar {
            ToolbarItemGroup {
                Picker("Period", selection: Binding(get: { ref.period }, set: { p in ref = ReportRef(appId: ref.appId, period: p, start: Self.start(p, ref.start)); aiText = nil })) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.help("Previous")
                Button { step(1) } label: { Image(systemName: "chevron.right") }.help("Next")
                Button { Task { await narrate(report) } } label: { Label("Write with AI", systemImage: "text.badge.star") }
                    .disabled(busy)
                Button { model.chatContext = report.plainText; model.ask("Walk me through this report. What stands out and what should I do next?") } label: {
                    Label("Chat about this", systemImage: "bubble.left")
                }
            }
        }
    }

    private func header(_ r: Report, _ app: AppRecord?) -> some View {
        HStack(spacing: 16) {
            if let app { AppIconView(app: app, size: 64) }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.appName).font(.largeTitle.weight(.bold))
                Text("\(r.period.title) report · \(r.periodLabel)").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func kpiCard(_ k: Report.KPI, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(k.metric == .activeSubs ? "Active subscriptions" : k.metric.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(k.metric.format(k.value)).font(.title2.weight(.semibold)).monospacedDigit()
            ChangeLabel(change: k.change)
            Sparkline(points: k.spark, tint: tint).frame(height: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    private func step(_ dir: Int) {
        let c: Calendar.Component = ref.period == .week ? .weekOfYear : ref.period == .month ? .month : .year
        let d = Day.calendar.date(byAdding: c, value: dir, to: Day.date(ref.start))!
        ref = ReportRef(appId: ref.appId, period: ref.period, start: Day.string(d))
        aiText = nil
    }

    static func start(_ p: ReportPeriod, _ day: String) -> String {
        switch p {
        case .week: Day.weekStart(day)
        case .month: Day.monthStart(day)
        case .year: Day.yearStart(day)
        }
    }

    private func narrate(_ r: Report) async {
        busy = true; defer { busy = false }
        do {
            aiText = try await AISettings.assistant.ask(
                "Write a 120-word narrative of this report for the developer: what happened, the most likely cause, and one thing to do next. Use only these numbers.",
                context: r.plainText)
        } catch { self.error = error.localizedDescription }
    }
}
