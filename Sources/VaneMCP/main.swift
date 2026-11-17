import Foundation
import SQLite3

// Read-only MCP server (stdio, JSON-RPC per line) over Vane's local database.
// The database is opened with SQLITE_OPEN_READONLY, so no tool can change anything.
// Credentials live in the Keychain, never in this file.

let dbPath = CommandLine.arguments.dropFirst().first
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Almanac/almanac.sqlite").path
let maxRows = 500

let guide = """
Vane stores App Store Connect data in SQLite. Tables:
- apps(id, name, bundle_id, hue)
- daily(app_id, day 'YYYY-MM-DD', metric, territory, value): one row per app, day, metric, territory. territory '' is the worldwide total; other values are ISO country codes (US, DE…). Never add '' to the countries or you count twice.
  Stored metrics: impressions, unique_impressions, browse_impressions, search_impressions, page_views (App Analytics, per territory),
  first_downloads, redownloads, sales (USD, customer price) (sales reports, per territory), proceeds (USD, developer share, worldwide only),
  sessions, crashes, ratings_total (running total).
  Not stored, compute them: downloads = first_downloads + redownloads; tap-through rate = SUM(page_views)/SUM(impressions);
  conversion rate = SUM(first_downloads + redownloads)/SUM(impressions) over days that have impressions (Apple's definition).
  Analytics metrics lag 2 to 3 days behind sales metrics; compare periods that both cover.
- versions(app_id, day, version, title): releases.
- events(id, app_id, day, title): campaigns, promos, press the user noted. app_id '' applies to every app. Use them to explain jumps.
- reviews(id, app_id, rating 1-5, title, body, reviewer, territory, created, response).
- listing(app_id, locale, name, subtitle, keywords, promo, description, …): the App Store page per language.
- sources(app_id, report, day, territory, download_type, source_type, source_info, value): downloads by where they came from.
  source_type: App Store search, App Store browse, App referrer, Web referrer, Unavailable…
  report 'standard' is complete and per territory, with no names. report 'detailed' names the referring app (bundle id) or website in source_info,
  but Apple leaves out small rows for privacy, so it covers fewer downloads. Never add the two reports together.
  Starts when Apple's analytics reports start, often later than daily downloads.
- ranks(app_id, day, country, term, rank): position of the app when searching each keyword of its listing, checked once a day
  in its top countries (lowercase ISO code) through Apple's public search API. rank 0 = not in the first 200. Close to, not identical to, the App Store's order.
- insights(id, app_id, day, json, dismissed, notified): what Vane flagged; json holds title, body, chart.
- meta(key, value): sync bookkeeping.
"""

let tools: [[String: Any]] = [
    ["name": "schema", "description": "Explains Vane's tables, metrics and how to compute rates. Call it first.",
     "inputSchema": ["type": "object", "properties": [String: Any]()]],
    ["name": "query", "description": "Runs one read-only SQL SELECT on Vane's database and returns rows as JSON (at most \(maxRows)).",
     "inputSchema": ["type": "object", "properties": ["sql": ["type": "string", "description": "A single SELECT (or WITH … SELECT) statement"]], "required": ["sql"]]],
]

var db: OpaquePointer?

func runQuery(_ sql: String) throws -> String {
    if db == nil {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            db = nil
            throw Failure("Cannot open \(dbPath). Open Vane once so it creates its database.")
        }
        sqlite3_busy_timeout(db, 5000)
    }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw Failure(String(cString: sqlite3_errmsg(db))) }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_stmt_readonly(stmt) != 0 else { throw Failure("Only read-only statements are allowed.") }
    var rows: [[String: Any]] = []
    var truncated = false
    while true {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE { break }
        guard rc == SQLITE_ROW else { throw Failure(String(cString: sqlite3_errmsg(db))) }
        if rows.count == maxRows { truncated = true; break }
        var row: [String: Any] = [:]
        for c in 0..<sqlite3_column_count(stmt) {
            let name = String(cString: sqlite3_column_name(stmt, c))
            switch sqlite3_column_type(stmt, c) {
            case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, c)
            case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, c)
            case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, c))
            default: row[name] = NSNull()
            }
        }
        rows.append(row)
    }
    let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self) + (truncated ? "\n(truncated at \(maxRows) rows: aggregate or add LIMIT)" : "")
}

struct Failure: Error { let message: String; init(_ m: String) { message = m } }

func callTool(_ name: String, _ args: [String: Any]) -> [String: Any] {
    let text: String, isError: Bool
    do {
        switch name {
        case "schema": text = guide
        case "query":
            guard let sql = args["sql"] as? String else { throw Failure("Missing sql.") }
            text = try runQuery(sql)
        default: throw Failure("Unknown tool \(name).")
        }
        isError = false
    } catch let f as Failure { text = f.message; isError = true } catch { text = "\(error)"; isError = true }
    return ["content": [["type": "text", "text": text]], "isError": isError]
}

func handle(_ msg: [String: Any]) -> [String: Any]? {
    guard let id = msg["id"] else { return nil }   // notifications get no reply
    let params = msg["params"] as? [String: Any] ?? [:]
    let result: [String: Any]
    switch msg["method"] as? String {
    case "initialize":
        result = ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                  "capabilities": ["tools": [String: Any]()],
                  "serverInfo": ["name": "vane", "version": "1.0"],
                  "instructions": "Read-only access to the user's App Store Connect data as synced by Vane. Call schema first, then query."]
    case "tools/list": result = ["tools": tools]
    case "tools/call": result = callTool(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
    case "ping": result = [:]
    default: return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]]
    }
    return ["jsonrpc": "2.0", "id": id, "result": result]
}

while let line = readLine() {
    guard let data = line.data(using: .utf8), !line.isEmpty,
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    if let reply = handle(msg), let out = try? JSONSerialization.data(withJSONObject: reply) {
        FileHandle.standardOutput.write(out + Data("\n".utf8))
    }
}
