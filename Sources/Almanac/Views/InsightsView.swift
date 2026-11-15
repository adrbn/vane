import AlmanacCore
import Charts
import SwiftUI

struct LegacyInsightsView: View {
    @Environment(AppModel.self) private var model
    @State private var category: InsightCategory?
    @State private var attentionFirst = false
    @State private var showDismissed = false
    @State private var fixing: Insight?

    var body: some View {
        let all = model.store.insights(model.appId ?? "", includeDismissed: showDismissed)
        let shown = all.filter { category == nil || $0.category == category }
            .sorted { attentionFirst && $0.needsAttention != $1.needsAttention ? $0.needsAttention : $0.day > $1.day }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(counts: Dictionary(grouping: all, by: \.category).mapValues(\.count))
                if shown.isEmpty {
                    EmptyHint(title: String(localized: "Nothing to flag"), message: String(localized: "Vane checks your data after every refresh and lists what's worth knowing here."), symbol: "checkmark.seal")
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(shown) { InsightCard(insight: $0, fixing: $fixing) }
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $fixing) { KeywordFixSheet(insight: $0) }
        .onAppear { model.chatContext = Self.context(shown, app: model.app?.name ?? "") }
    }

    private func header(counts: [InsightCategory: Int]) -> some View {
        HStack(spacing: 10) {
            Picker("Category", selection: $category) {
                Text("All insights").tag(InsightCategory?.none)
                Divider()
                ForEach(InsightCategory.allCases.filter { counts[$0] != nil }) { c in
                    Label("\(c.title) (\(counts[c] ?? 0))", systemImage: c.symbol).tag(InsightCategory?.some(c))
                }
            }
            .labelsHidden().fixedSize()
            Spacer()
            Toggle("Needs attention first", isOn: $attentionFirst).checkboxStyle()
            Menu {
                Toggle("Show dismissed", isOn: $showDismissed)
                Button("Restore all dismissed") { try? model.store.restoreDismissed(model.appId ?? ""); model.revision += 1 }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    static func context(_ insights: [Insight], app: String) -> String {
        "Screen: Insights for \(app)\n" + insights.prefix(30).map { "- [\($0.category.title), \($0.day)] \($0.title): \($0.body)" }.joined(separator: "\n")
    }
}

struct InsightCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var insight: Insight
    @Binding var fixing: Insight?

    var body: some View {
        let tint = insight.category.tint
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: insight.category.symbol).foregroundStyle(tint).font(.callout.weight(.semibold))
                Text(insight.category.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if insight.needsAttention {
                    Circle().fill(.orange).frame(width: 6, height: 6).help("Needs attention")
                }
                Spacer()
                Text(Day.date(insight.day).formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                if !insight.dismissed {
                    Button { withAnimation(.snappy) { model.dismiss(insight) } } label: {
                        Image(systemName: "xmark").font(.caption2.weight(.bold)).frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Dismiss")
                }
            }
            Text(insight.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(insight.body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let chart = insight.chart { InsightChartView(chart: chart, tint: tint) }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .card()
        .opacity(insight.dismissed ? 0.55 : 1)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            Button { model.ask(String(localized: "Explain this insight and what I should do about it: \(insight.title). \(insight.body)")) } label: {
                Label("Ask", systemImage: "bubble.left")
            }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            Spacer()
            switch insight.action {
            case .fixKeywords: Button("Fix…") { fixing = insight }.controlSize(.small)
            case .openReport(let p, let s):
                Button("Read report") { openWindow(id: "report", value: ReportRef(appId: insight.appId, period: ReportPeriod(rawValue: p) ?? .week, start: s)) }
                    .controlSize(.small)
            case .openMetric(let m):
                Button("Open") {
                    switch m {
                    case "listing": model.section = .listing
                    case "reviews": model.section = .reviews
                    case "territories": model.section = .territories
                    case "sales": model.section = .sales
                    default: if let metric = Metric(rawValue: m) { model.section = .metric(metric) }
                    }
                }
                .controlSize(.small)
            case nil: EmptyView()
            }
        }
    }
}

struct InsightChartView: View {
    var chart: InsightChart
    var tint: Color

    var body: some View {
        if chart.isBigNumber {
            Text(chart.headline)
                .font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chart.label).font(.caption.weight(.medium))
                    Spacer()
                    Text(chart.headline).font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                }
                Chart {
                    ForEach(chart.points) { p in
                        AreaMark(x: .value("Day", p.date), y: .value("Value", p.value))
                            .foregroundStyle(.linearGradient(colors: [tint.opacity(0.2), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", p.date), y: .value("Value", p.value)).foregroundStyle(tint).lineStyle(.init(lineWidth: 1.6))
                    }
                    if let b = chart.baseline {
                        RuleMark(y: .value("Baseline", b))
                            .foregroundStyle(.secondary).lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text(chart.baselineLabel ?? Int(b).formatted()).font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) }
                }
                .frame(height: 96)
            }
            .padding(10)
            .background(tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct KeywordFixSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var insight: Insight
    /// Set when shown as a centered overlay instead of a system sheet.
    var close: (() -> Void)? = nil
    @State private var keywords = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let locale: String = { if case .fixKeywords(let l, _)? = insight.action { return l }; return "" }()
        let listing = model.store.listing(insight.appId).first { $0.locale == locale }
        VStack(alignment: .leading, spacing: 14) {
            Text("Fix keywords · \(Locale.current.localizedString(forIdentifier: locale) ?? locale)").font(.title3.weight(.semibold))
            Text(insight.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LabeledContent("Now") { Text(listing?.keywords ?? "").textSelection(.enabled).foregroundStyle(.secondary) }
            VStack(alignment: .trailing, spacing: 4) {
                TextField("Keywords", text: $keywords, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                Text("\(keywords.count) / 100").font(.caption).monospacedDigit().foregroundStyle(keywords.count > 100 ? .red : .secondary)
            }
            Text("Add new comma-separated words in the space you freed. Don't repeat words from your name or subtitle.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Suggest words with AI") { Task { await suggest(listing) } }.disabled(busy)
                Spacer()
                Button("Cancel") { done() }.keyboardShortcut(.cancelAction)
                Button(model.isDemo ? String(localized: "Apply (demo)") : String(localized: "Apply to App Store Connect")) { Task { await apply(listing) } }
                    .keyboardShortcut(.defaultAction).disabled(busy || keywords.count > 100 || listing == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { if case .fixKeywords(_, let k)? = insight.action { keywords = k } }
    }

    private func done() { if let close { close() } else { dismiss() } }

    private func suggest(_ l: ListingLocale?) async {
        guard let l else { return }
        busy = true; defer { busy = false }
        let a = Assistant(provider: Assistant.Provider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .claude)
        do {
            let out = try await a.ask("Return ONLY the improved keyword field: comma-separated, no spaces, at most 100 characters, in the listing's language, no words already in the name or subtitle. Keep the strongest existing terms.",
                                      context: "Locale: \(l.locale)\nName: \(l.name)\nSubtitle: \(l.subtitle)\nCurrent keywords: \(keywords)\nDescription: \(l.description.prefix(1500))")
            keywords = out.components(separatedBy: .newlines).last { !$0.isEmpty }?.replacingOccurrences(of: ", ", with: ",") ?? keywords
        } catch { self.error = error.localizedDescription }
    }

    private func apply(_ l: ListingLocale?) async {
        guard var l else { return }
        busy = true; defer { busy = false }
        do {
            if let syncer = model.syncer { try await syncer.updateKeywords(l, keywords: keywords) }
            else { l.keywords = keywords; try model.store.upsert(listing: l) }
            try model.store.dismiss(insight: insight.id)
            model.runEngine(); model.revision += 1
            done()
        } catch { self.error = error.localizedDescription }
    }
}
