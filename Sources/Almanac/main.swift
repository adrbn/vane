import Foundation

// The UI follows the language picked in Settings (English with en_US numbers and dates by default, whatever the Mac's region),
// including strings built in AlmanacCore. Set before anything reads Locale.current, which is cached on first use.
let language = AppLanguage.current
UserDefaults.standard.set(language.locale, forKey: "AppleLocale")
UserDefaults.standard.set([language.id], forKey: "AppleLanguages")

if CommandLine.arguments.contains("--sync") {
    BackgroundAgent.runHeadless()
    exit(0)
}
// Launch flags take values (`--pane sales`); without this AppKit opens the value as a file and SwiftUI skips the main window.
UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
AlmanacApp.main()
