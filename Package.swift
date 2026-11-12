// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Almanac",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "AlmanacCore", path: "Sources/AlmanacCore"),
        .executableTarget(name: "Almanac", dependencies: ["AlmanacCore"], path: "Sources/Almanac"),
        .testTarget(name: "AlmanacTests", dependencies: ["AlmanacCore"], path: "Tests/AlmanacTests"),
    ],
    swiftLanguageModes: [.v5]
)
