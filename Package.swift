// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenToMeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ListenToMeCore", targets: ["ListenToMeCore"])
    ],
    targets: [
        .target(name: "ListenToMeCore"),
        .testTarget(name: "ListenToMeCoreTests", dependencies: ["ListenToMeCore"])
    ]
)
