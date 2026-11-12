import Foundation

/// `vane://setup#<base64url JSON>`: the Mac shows it as a QR code, the iPhone's Camera opens it in Vane.
/// The key travels in the fragment, screen to camera, never over the network.
public enum SetupLink {
    public static func url(for c: ASCCredentials) -> URL {
        let fields = ["i": c.issuerId, "k": c.keyId, "p": c.privateKeyPEM, "v": c.vendorNumber]
        let json = (try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)) ?? Data()
        let b64 = json.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "vane://setup#\(b64)")!
    }

    public static func credentials(from url: URL) -> ASCCredentials? {
        guard url.scheme == "vane", url.host == "setup", var b64 = url.fragment else { return nil }
        b64 = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let f = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return nil }
        let c = ASCCredentials(issuerId: f["i"] ?? "", keyId: f["k"] ?? "", privateKeyPEM: f["p"] ?? "", vendorNumber: f["v"] ?? "")
        return c.isComplete ? c : nil
    }
}
