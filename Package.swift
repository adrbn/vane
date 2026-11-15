// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Almanac",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.library(name: "AlmanacCore", targets: ["AlmanacCore"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")],
    targets: [
        .target(name: "AlmanacCore", path: "Sources/AlmanacCore"),
        .executableTarget(name: "Almanac", dependencies: ["AlmanacCore", .product(name: "Sparkle", package: "Sparkle")], path: "Sources/Almanac"),
        .executableTarget(name: "vane-mcp", path: "Sources/VaneMCP"),
        .testTarget(name: "AlmanacTests", dependencies: ["AlmanacCore"], path: "Tests/AlmanacTests"),
    ],
    swiftLanguageModes: [.v5]
)
