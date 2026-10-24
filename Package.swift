// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenToMeCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ListenToMeCore", targets: ["ListenToMeCore"])
    ],
    targets: [
        .target(name: "ListenToMeCore"),
        // Golden export files are read from the source tree (SessionExportGoldenTests), not bundled.
        .testTarget(name: "ListenToMeCoreTests", dependencies: ["ListenToMeCore"], exclude: ["Golden"])
    ]
)
