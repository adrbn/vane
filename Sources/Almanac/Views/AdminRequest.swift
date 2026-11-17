import AlmanacCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The key is Sales and Reports: Apple lets only an Admin key turn the analytics reports on, once per app.
/// Two ways through, neither of which stores an Admin key.
struct AdminRequestCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var sheet = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "key").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.accentText)
                    .frame(width: 36, height: 36).background(t.accentSoft, in: RoundedRectangle(cornerRadius: t.inner(14), style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("One step needs an Admin key").font(t.font(17, .bold))
                    Text("Your key reads sales, and it can read Apple’s analytics too, but Apple lets only an Admin key switch those reports on. It’s done once per app, by anyone on the team. After that, your key keeps working on its own.")
                        .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                SmallButton(label: String(localized: "Use an Admin Key Once…"), prominent: true) { sheet = true }
                SmallButton(label: copied ? String(localized: "Copied") : String(localized: "Copy a Message for Your Admin")) {
                    Pasteboard.copy(Self.message(model.appsNeedingAdmin.map(\.name)))
                    copied = true
                }
            }
            .padding(.leading, 50)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .sheet(isPresented: $sheet) { AdminKeySheet() }
    }

    static func message(_ apps: [String]) -> String {
        String(localized: """
        Hi! Could you turn on App Store Connect's analytics reports for \(apps.formatted(.list(type: .and)))? It takes an Admin API key and a single request per app:

        POST https://api.appstoreconnect.apple.com/v1/analyticsReportRequests
        {"data":{"type":"analyticsReportRequests","attributes":{"accessType":"ONGOING"},"relationships":{"app":{"data":{"type":"apps","id":"APP_ID"}}}}}

        Or open Vane (github.com/adrbn/vane) with your Admin key once: it sends that request and doesn't keep the key. Thanks!
        """)
    }
}

/// Takes an Admin .p8 for one request per app, keeps it in memory only, then forgets it.
struct AdminKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var creds = ASCCredentials(issuerId: Keychain.credentials().issuerId, keyId: "", privateKeyPEM: "", vendorNumber: "")
    @State private var importing = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Turn on Apple’s analytics").font(t.font(20, .bold))
            Text("Vane sends one request per app with this key, then forgets it. It isn’t saved to the Keychain or to disk. If you made the key just for this, you can revoke it right after in App Store Connect.")
                .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
            LabeledContent(String(localized: "Issuer ID")) { TextField("", text: $creds.issuerId).textFieldStyle(.roundedBorder).frame(width: 300) }
            LabeledContent(String(localized: "Admin Key ID")) { TextField("", text: $creds.keyId).textFieldStyle(.roundedBorder).frame(width: 300) }
            LabeledContent(String(localized: "Private key")) {
                HStack {
                    Text(creds.privateKeyPEM.isEmpty ? String(localized: "Drop the .p8 here") : String(localized: "Loaded")).foregroundStyle(t.label2)
                    SmallButton(label: String(localized: "Choose File…")) { importing = true }
                }
            }
            if let error { Text(error).font(t.font(12)).foregroundStyle(t.neg).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                SmallButton(label: String(localized: "Cancel")) { dismiss() }
                SmallButton(label: working ? String(localized: "Sending…") : String(localized: "Turn On Analytics"), prominent: true, busy: working) { Task { await send() } }
                    .disabled(!creds.isComplete || working)
            }
        }
        .padding(24).frame(width: 520)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "p8" }) else { return false }
            AccountSettings.load(url, into: &creds); return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: AccountSettings.keyTypes) { result in
            if case .success(let url) = result { AccountSettings.load(url, into: &creds) }
        }
    }

    private func send() async {
        working = true; error = nil
        defer { working = false }
        let syncer = Syncer(client: ASCClient(credentials: creds), store: model.store)
        do {
            for app in model.appsNeedingAdmin { try await syncer.requestAnalytics(app: app.id) }
        } catch ASCError.http(403, _) {
            error = String(localized: "Apple refused this key too. Check that its role is Admin."); return
        } catch {
            self.error = error.localizedDescription; return
        }
        creds = ASCCredentials(issuerId: "", keyId: "", privateKeyPEM: "", vendorNumber: "")
        model.revision += 1
        dismiss()
    }
}

enum Pasteboard {
    static func copy(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.string = s
        #endif
    }
}
