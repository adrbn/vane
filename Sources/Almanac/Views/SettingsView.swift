import AlmanacCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import CoreImage.CIFilterBuiltins
#endif

struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @State private var creds = Keychain.credentials()
    @State private var status: String?
    @State private var testing = false
    @State private var importing = false
    @State private var showingQR = false
    #if os(macOS)
    @State private var agentOn = BackgroundAgent.isEnabled
    #endif

    var body: some View {
        Form {
            Section {
                field("Issuer ID", $creds.issuerId)
                field("Key ID", $creds.keyId)
                LabeledContent("Private key") {
                    HStack {
                        (creds.privateKeyPEM.isEmpty ? Text("None") : Text("AuthKey loaded")).foregroundStyle(.secondary)
                        Button("Choose .p8…") { importing = true }
                    }
                }
                field("Vendor number", $creds.vendorNumber, prompt: "e.g. 87654321")
            } footer: {
                Text("Create a key in App Store Connect › Users and Access › Integrations. The Sales and Reports role is enough for analytics and sales; replying to reviews and editing keywords need Customer Support / App Manager. The key is stored in your Keychain and only sent to Apple.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #if os(macOS)
            if Keychain.credentials().isComplete {
                Section {
                    Button("Set up Vane on iPhone…") { showingQR = true }
                    Text("Shows a QR code. Scan it with the iPhone's Camera and Vane connects with this key.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .sheet(isPresented: $showingQR) { SetupQR(url: SetupLink.url(for: Keychain.credentials())) }
            }
            Section {
                Toggle("Check for new data in the background", isOn: $agentOn)
                    .onChange(of: agentOn) { _, on in
                        do { try BackgroundAgent.setEnabled(on) } catch { status = error.localizedDescription; agentOn = BackgroundAgent.isEnabled }
                    }
                Text("Every 6 hours, even when Vane is closed. You'll get a notification when something needs attention.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif
            HStack {
                if let status { Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
                Spacer()
                if model.isDemo == false && !creds.isComplete { Button("Show demo data") { model.loadDemo() } }
                Button("Save and connect") { Task { await save() } }.keyboardShortcut(.defaultAction).disabled(!creds.isComplete || testing)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.keyTypes) { result in
            guard case .success(let url) = result else { return }
            Self.load(url, into: &creds)
        }
    }

    static let keyTypes = [UTType(filenameExtension: "p8") ?? .data, .data]

    static func load(_ url: URL, into creds: inout ASCCredentials) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        creds.privateKeyPEM = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // AuthKey_<KEYID>.p8 → fill the key ID for free.
        if creds.keyId.isEmpty, let m = url.lastPathComponent.firstMatch(of: #/AuthKey_([A-Z0-9]+)\.p8/#) { creds.keyId = String(m.1) }
    }

    @ViewBuilder private func field(_ label: LocalizedStringKey, _ text: Binding<String>, prompt: LocalizedStringKey? = nil) -> some View {
        #if os(macOS)
        TextField(label, text: text, prompt: prompt.map { Text($0) })
        #else
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt ?? "Required"))
                .multilineTextAlignment(.trailing).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        #endif
    }

    private func save() async {
        testing = true; defer { testing = false }
        do {
            _ = try await ASCClient(credentials: creds).json("v1/apps", query: ["limit": "1"])
            Keychain.save(creds)
            status = String(localized: "Connected. Importing your data…")
            await model.refresh()
            status = model.syncErrors.isEmpty ? String(localized: "All set.") : model.syncErrors.joined(separator: "\n")
        } catch { status = error.localizedDescription }
    }
}

#if os(macOS)
/// The key is in this code: shown only on request, nothing is saved or sent.
struct SetupQR: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.blocks.id

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Vane on iPhone").font(t.font(20, .bold))
                Text("Scan once and the iPhone uses the same key.").font(t.font(13)).foregroundStyle(t.label2)
            }
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 240, height: 240)
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: t.rS + 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 8) {
                step(t, 1, "Install Vane on the iPhone and open it.")
                step(t, 2, "Tap Scan the Code on Your Mac, or point the Camera here.")
                step(t, 3, "Confirm. Your numbers load in a few seconds.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard(padding: 14, radius: t.rS + 2)
            Label("This code holds your private key. Don't screenshot or share it.", systemImage: "lock.fill")
                .font(t.font(11)).foregroundStyle(t.label2)
            SmallButton(label: "Done", prominent: true) { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .foregroundStyle(t.label)
        .padding(28).frame(width: 400)
        .background(ThemeBackground())
        .environment(\.theme, t)
    }

    private func step(_ t: AlmanacTheme, _ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(t.font(11, .bold)).foregroundStyle(t.accent)
                .frame(width: 20, height: 20).background(t.accentSoft, in: Circle())
            Text(text).font(t.font(13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var image: NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(url.absoluteString.utf8)
        f.correctionLevel = "L"
        guard let out = f.outputImage, let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: out.extent.size)
    }
}
#endif
