import AlmanacCore
import SwiftUI
import WidgetKit
import os

/// Writes the widget snapshot for the selected app, then asks WidgetKit to redraw.
enum WidgetFeed {
    @MainActor static func write(_ model: AppModel, theme t: AlmanacTheme) {
        guard let app = model.app else { return }
        let store = model.store
        let s = store.series(app.id, .firstDownloads)
        guard let last = s.last else { return }
        let weekAgo = s.last { $0.day == Day.add(-7, to: last.day) }
        let change = weekAgo.map { Change(.firstDownloads, value: last.value, previous: $0.value) }
        let d = AppStoreData(store: store, app: app.id, days: 28)
        let month: [VaneSnapshot.Stat] = [(Metric.firstDownloads, "Downloads"), (.ttr, "Tap-through"), (.pageCR, "Conversion")]
            .filter { d.has($0.0) }
            .map { m, label in .init(label: label, value: Num.value(m, d.value(m))) }
        let reviews = store.reviews(app.id)
        let a = t.accent.resolve(in: EnvironmentValues())
        let snap = VaneSnapshot(
            app: app.name, day: InsightCardView.when(last.day), downloads: Num.int(last.value),
            change: change?.text, up: change?.up ?? true, spark: s.suffix(28).map(\.value), month: month,
            rating: reviews.isEmpty ? nil : ReviewInfo.average(reviews), reviews: reviews.count,
            needsReply: reviews.filter { $0.response == nil }.count,
            accent: [Double(a.red), Double(a.green), Double(a.blue)], updated: .now)
        do {
            try snap.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Logger(subsystem: "com.adrbn.vane", category: "widget").error("Widget snapshot not written: \(error.localizedDescription)")
        }
    }
}
