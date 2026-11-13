import Foundation

/// What the widgets show, written by the app into the shared App Group after every sync.
/// Strings are formatted by the app so the widget needs none of Vane's code.
struct VaneSnapshot: Codable {
    struct Stat: Codable { var label: String; var value: String }

    var app: String
    var day: String              // "Yesterday", "Nov 11"
    var downloads: String
    var change: String?          // vs the same day last week
    var up: Bool
    var spark: [Double]          // last 28 days
    var month: [Stat]            // last 28 days: downloads, tap-through, conversion
    var rating: Double?
    var reviews: Int
    var needsReply: Int
    var accent: [Double]         // r, g, b of the chosen look
    var updated: Date

    static let group = "group.com.adrbn.vane"
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget.json")
    }

    static func load() -> VaneSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VaneSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.url else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Widget gallery and first install, before the app has synced.
    static let sample = VaneSnapshot(
        app: "Vane", day: "Yesterday", downloads: "130", change: "↑ 8.2%", up: true,
        spark: [92, 104, 98, 120, 111, 96, 118, 124, 109, 101, 127, 119, 113, 130, 122, 117, 126, 135, 121, 114, 129, 138, 125, 119, 133, 141, 128, 130],
        month: [.init(label: "Downloads", value: "4,022"),
                .init(label: "Tap-through", value: "8.5%"),
                .init(label: "Conversion", value: "22.5%")],
        rating: 4.6, reviews: 48, needsReply: 3, accent: [0.27, 0.2, 0.89], updated: .now)
}
