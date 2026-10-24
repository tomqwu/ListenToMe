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
        .testTarget(name: "ListenToMeCoreTests", dependencies: ["ListenToMeCore"])
    ]
)
