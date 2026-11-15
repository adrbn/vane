import Foundation

/// A button the assistant can suggest under its answer. It writes `[[open:reviews?filter=unanswered|Unanswered reviews]]`
/// or `[[pin:page_cr]]` in its text; only the destinations and values listed here are kept, everything else is dropped.
/// Following a link only navigates or pins a chart: nothing is ever sent, edited or deleted.
public struct AssistantLink: Hashable, Sendable {
    public enum Action: Hashable, Sendable { case open(pane: String), pin(Metric) }

    public var action: Action
    public var label: String
    public var period: Int?        // 7, 28, 90 or 365 days
    public var locale: String?     // listing language, e.g. de-DE
    public var country: String?    // reviews territory, ISO alpha-2
    public var rating: Int?        // reviews, 1…5
    public var unanswered = false  // reviews without a reply

    public static let panes = ["insights", "listing", "reviews", "appStore", "sales", "usage", "territories"]
    static let periods = [7, 28, 90, 365]

    /// The text without the tags, and the valid links in order (at most 3, no duplicates).
    public static func extract(from text: String) -> (text: String, links: [AssistantLink]) {
        guard let re = try? NSRegularExpression(pattern: #"\[\[(open|pin):([^\]\|]{1,120})(?:\|([^\]]{1,60}))?\]\]"#) else { return (text, []) }
        let ns = text as NSString
        var links: [AssistantLink] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let label = m.range(at: 3).location == NSNotFound ? nil : ns.substring(with: m.range(at: 3))
            if let l = parse(kind: ns.substring(with: m.range(at: 1)), target: ns.substring(with: m.range(at: 2)), label: label),
               !links.contains(where: { $0.action == l.action && $0.locale == l.locale && $0.country == l.country && $0.rating == l.rating && $0.unanswered == l.unanswered }) {
                links.append(l)
            }
        }
        let clean = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, Array(links.prefix(3)))
    }

    static func parse(kind: String, target: String, label: String?) -> AssistantLink? {
        let parts = target.split(separator: "?", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let path = parts.first ?? ""
        let action: Action
        if kind == "pin" {
            guard let m = Metric(rawValue: path) else { return nil }
            action = .pin(m)
        } else if path.hasPrefix("metric:") {
            guard Metric(rawValue: String(path.dropFirst(7))) != nil else { return nil }
            action = .open(pane: path)
        } else {
            guard panes.contains(path) else { return nil }
            action = .open(pane: path)
        }
        var link = AssistantLink(action: action, label: label.map(clean) ?? "")
        let query = parts.count > 1 ? parts[1] : ""
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "period": link.period = Int(kv[1]).flatMap { periods.contains($0) ? $0 : nil }
            case "locale" where path == "listing":
                link.locale = kv[1].range(of: #"^[a-z]{2,3}(-[A-Za-z]{2,4})?$"#, options: .regularExpression) != nil ? kv[1] : nil
            case "country" where path == "reviews":
                link.country = kv[1].range(of: "^[A-Z]{2}$", options: .regularExpression) != nil ? kv[1] : nil
            case "rating" where path == "reviews": link.rating = Int(kv[1]).flatMap { (1...5).contains($0) ? $0 : nil }
            case "filter" where path == "reviews": link.unanswered = kv[1] == "unanswered"
            default: break
            }
        }
        return link
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"[\p{Cc}\[\]]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// Taught to the assistant in its system prompt.
    public static let prompt = """
    You can add up to 3 buttons under your answer that take the developer to the right place in Vane. Put each on its own line at the end:
    [[open:DESTINATION|short label]] where DESTINATION is one of insights, listing, reviews, appStore, sales, usage, territories, or metric:NAME
    (NAME: impressions, unique_impressions, page_views, first_downloads, redownloads, downloads, sales, proceeds, sessions, crashes, ttr, page_cr).
    Options after "?", joined with "&": period=7|28|90|365 (any screen); listing: locale=de-DE; reviews: country=DE, rating=1-5, filter=unanswered.
    [[pin:NAME|short label]] pins that chart in the sidebar.
    Example: [[open:reviews?filter=unanswered&rating=1|Unanswered 1-star reviews]]. Labels in the developer's language, under 30 characters.
    Only add a button when it points to what your answer talks about.
    """
}
