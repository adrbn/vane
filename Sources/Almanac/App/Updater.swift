import Sparkle
import SwiftUI

/// Sparkle, with its standard window: a daily background check, and "Check for Updates…" in the app menu.
/// Updates are EdDSA-signed (SUPublicEDKey in Info.plist) and must carry the same Developer ID as the installed copy.
@MainActor
enum Updater {
    // `--demo` windows never update: they run from build folders, not /Applications.
    static let controller: SPUStandardUpdaterController? = CommandLine.arguments.contains("--demo")
        ? nil : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    static var menuItem: some View {
        Button("Check for Updates…") { controller?.checkForUpdates(nil) }.disabled(controller == nil)
    }
}
