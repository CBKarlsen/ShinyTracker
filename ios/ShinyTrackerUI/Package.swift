// swift-tools-version: 6.0
import PackageDescription

// macOS is here so `swift build` / `swift test` run headlessly on a Mac, same as
// ShinyTrackerAPI and ShinyTrackerAuth. It is not a shipping platform for this app.
let package = Package(
    name: "ShinyTrackerUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShinyTrackerUI", targets: ["ShinyTrackerUI"])
    ],
    targets: [
        // No dependencies — SwiftUI only. These are the design tokens, nothing else:
        // the odds engine, the API client and the session must not leak into them.
        .target(name: "ShinyTrackerUI"),
        .testTarget(name: "ShinyTrackerUITests", dependencies: ["ShinyTrackerUI"]),
    ]
)
