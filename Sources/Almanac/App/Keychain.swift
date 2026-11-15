import AlmanacCore
import Foundation
import Security

/// The App Store Connect key lives in the login Keychain, never in a file or UserDefaults.
enum Keychain {
    private static let service = "dev.almanac.asc"
    /// Demo windows never touch the real key: no Keychain prompt, and nothing real on screen.
    private static let off = CommandLine.arguments.contains("--demo")

    static func credentials() -> ASCCredentials {
        ASCCredentials(issuerId: read("issuer") ?? "", keyId: read("keyId") ?? "", privateKeyPEM: read("p8") ?? "",
                       vendorNumber: read("vendor") ?? "")
    }

    static func save(_ c: ASCCredentials) {
        write("issuer", c.issuerId); write("keyId", c.keyId); write("p8", c.privateKeyPEM); write("vendor", c.vendorNumber)
    }

    static func clear() { for k in ["issuer", "keyId", "p8", "vendor"] { delete(k) } }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> String? {
        guard !off else { return nil }
        var q = query(account)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    private static func write(_ account: String, _ value: String) {
        guard !off else { return }
        delete(account)
        guard !value.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock // the background agent runs while locked screens
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func delete(_ account: String) { if !off { SecItemDelete(query(account) as CFDictionary) } }
}
