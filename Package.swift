// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenToMeCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ListenToMeCore", targets: ["ListenToMeCore"])
    ],
    targets: [
        // The domain vocabularies are curated term lists the project writes itself (issue #222).
        .target(name: "ListenToMeCore", resources: [.copy("Resources/Vocabularies")]),
        // Golden export files are read from the source tree (SessionExportGoldenTests), not bundled.
        .testTarget(name: "ListenToMeCoreTests", dependencies: ["ListenToMeCore"], exclude: ["Golden"])
    ]
)
