import CryptoKit
import Foundation

public struct ASCCredentials: Sendable, Equatable {
    public var issuerId: String
    public var keyId: String
    public var privateKeyPEM: String
    public var vendorNumber: String
    public init(issuerId: String, keyId: String, privateKeyPEM: String, vendorNumber: String) {
        self.issuerId = issuerId; self.keyId = keyId; self.privateKeyPEM = privateKeyPEM; self.vendorNumber = vendorNumber
    }
    public var isComplete: Bool { !issuerId.isEmpty && !keyId.isEmpty && !privateKeyPEM.isEmpty }
}

public enum ASCError: Error, LocalizedError {
    case badKey
    case http(Int, String)
    case notFound
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .badKey: String(localized: "The private key couldn't be read. Paste the full contents of the AuthKey_XXXX.p8 file.")
        case .http(let code, let msg): String(localized: "App Store Connect returned \(code): \(msg)")
        case .notFound: String(localized: "No report is available for that day yet.")
        case .decoding(let m): String(localized: "Unexpected response: \(m)")
        }
    }
}

public typealias JSON = [String: Any]

/// Thin App Store Connect API client. Signs an ES256 JWT with CryptoKit.
public struct ASCClient: Sendable {
    public let credentials: ASCCredentials
    private let base = URL(string: "https://api.appstoreconnect.apple.com")!

    public init(credentials: ASCCredentials) { self.credentials = credentials }

    // MARK: auth

    public func token(now: Date = Date()) throws -> String {
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { throw ASCError.badKey }
        let header = ["alg": "ES256", "kid": credentials.keyId, "typ": "JWT"]
        let iat = Int(now.timeIntervalSince1970)
        let payload: [String: Any] = ["iss": credentials.issuerId, "iat": iat, "exp": iat + 1200, "aud": "appstoreconnect-v1"]
        let h = try JSONSerialization.data(withJSONObject: header, options: .sortedKeys).base64URL
        let p = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys).base64URL
        let sig = try key.signature(for: Data("\(h).\(p)".utf8)).rawRepresentation.base64URL
        return "\(h).\(p).\(sig)"
    }

    // MARK: transport

    public func request(_ path: String, method: String = "GET", query: [String: String] = [:], body: JSON? = nil) async throws -> Data {
        var url = path.hasPrefix("http") ? URL(string: path)! : base.appendingPathComponent(path)
        if !query.isEmpty {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = c.url!
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 404 { throw ASCError.notFound }
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? JSON)
                .flatMap { ($0["errors"] as? [JSON])?.first?["detail"] as? String } ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw ASCError.http(code, detail)
        }
        return data
    }

    public func json(_ path: String, method: String = "GET", query: [String: String] = [:], body: JSON? = nil) async throws -> JSON {
        let data = try await request(path, method: method, query: query, body: body)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? JSON else { throw ASCError.decoding(path) }
        return obj
    }

    /// Follows `links.next` up to `maxPages`. Returns all `data` items plus all `included`.
    public func all(_ path: String, query: [String: String] = [:], maxPages: Int = 10) async throws -> (data: [JSON], included: [JSON]) {
        var items: [JSON] = [], included: [JSON] = []
        var next: String? = path
        var q = query
        var pages = 0
        while let n = next, pages < maxPages {
            let page = try await json(n, query: q)
            items += page["data"] as? [JSON] ?? []
            included += page["included"] as? [JSON] ?? []
            next = (page["links"] as? JSON)?["next"] as? String
            q = [:] // next links already carry the query
            pages += 1
        }
        return (items, included)
    }
}

extension JSON {
    var id: String { self["id"] as? String ?? "" }
    var attrs: JSON { self["attributes"] as? JSON ?? [:] }
    func attr(_ k: String) -> String { attrs[k] as? String ?? "" }
    func rel(_ k: String) -> String? { (((self["relationships"] as? JSON)?[k] as? JSON)?["data"] as? JSON)?["id"] as? String }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Decodes a single-member gzip stream (what Apple's report endpoints return).
    public func gunzipped() throws -> Data {
        guard count > 18, self[startIndex] == 0x1f, self[startIndex + 1] == 0x8b else { return self } // already plain
        let b = [UInt8](self)
        let flags = b[3]
        var i = 10
        if flags & 0x04 != 0 { i += 2 + Int(b[i]) + Int(b[i + 1]) << 8 }
        if flags & 0x08 != 0 { while b[i] != 0 { i += 1 }; i += 1 }
        if flags & 0x10 != 0 { while b[i] != 0 { i += 1 }; i += 1 }
        if flags & 0x02 != 0 { i += 2 }
        let deflate = Data(b[i..<(b.count - 8)])
        return try (deflate as NSData).decompressed(using: .zlib) as Data
    }
}

/// Tab- or comma-separated report → array of header-keyed rows.
public func parseDelimited(_ text: String, separator: Character) -> [[String: String]] {
    var lines = text.split(whereSeparator: \.isNewline).map(String.init)
    guard !lines.isEmpty else { return [] }
    let header = splitRow(lines.removeFirst(), separator)
    return lines.map { line in
        let cols = splitRow(line, separator)
        var row: [String: String] = [:]
        for (i, h) in header.enumerated() where i < cols.count { row[h] = cols[i] }
        return row
    }
}

private func splitRow(_ line: String, _ sep: Character) -> [String] {
    guard sep == "," else { return line.split(separator: sep, omittingEmptySubsequences: false).map(String.init) }
    var out: [String] = [], cur = "", quoted = false
    for ch in line {
        if ch == "\"" { quoted.toggle() }
        else if ch == sep && !quoted { out.append(cur); cur = "" }
        else { cur.append(ch) }
    }
    out.append(cur)
    return out
}
