// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShinyTrackerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShinyTrackerKit", targets: ["ShinyTrackerKit"])
    ],
    targets: [
        .target(name: "ShinyTrackerKit"),
        .testTarget(name: "ShinyTrackerKitTests", dependencies: ["ShinyTrackerKit"]),
    ]
)
