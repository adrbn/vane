import Foundation

// The UI is English with en_US numbers and dates whatever the Mac's region ("Nov 11", "1,000"), including strings built in AlmanacCore.
// Set before anything reads Locale.current, which is cached on first use.
UserDefaults.standard.set("en_US", forKey: "AppleLocale")
UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")

if CommandLine.arguments.contains("--sync") {
    BackgroundAgent.runHeadless()
    exit(0)
}
// Launch flags take values (`--pane sales`); without this AppKit opens the value as a file and SwiftUI skips the main window.
UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
AlmanacApp.main()
