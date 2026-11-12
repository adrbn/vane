import Foundation

if CommandLine.arguments.contains("--sync") {
    BackgroundAgent.runHeadless()
    exit(0)
}
AlmanacApp.main()
