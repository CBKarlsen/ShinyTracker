// swift-tools-version: 6.0
import PackageDescription

// macOS is here so `swift build` / `swift test` run headlessly on a Mac, same as
// ShinyTrackerAuth. It is not a shipping platform for this app.
let package = Package(
    name: "ShinyTrackerAPI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShinyTrackerAPI", targets: ["ShinyTrackerAPI"])
    ],
    dependencies: [
        // Local paths, not remote — DECISIONS.md D2. No networking dependency:
        // URLSession is the whole transport.
        .package(path: "../ShinyTrackerKit"),
        .package(path: "../ShinyTrackerAuth"),
    ],
    targets: [
        .target(name: "ShinyTrackerAPI", dependencies: ["ShinyTrackerKit", "ShinyTrackerAuth"]),
        .testTarget(name: "ShinyTrackerAPITests", dependencies: ["ShinyTrackerAPI"]),
    ]
)
