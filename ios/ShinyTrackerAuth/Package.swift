// swift-tools-version: 6.0
import PackageDescription

// macOS is here so `swift build` / `swift test` run headlessly on a Mac.
// It is not a shipping platform for this app.
let package = Package(
    name: "ShinyTrackerAuth",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShinyTrackerAuth", targets: ["ShinyTrackerAuth"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "ShinyTrackerAuth",
            dependencies: [.product(name: "Auth", package: "supabase-swift")]
        ),
        .testTarget(name: "ShinyTrackerAuthTests", dependencies: ["ShinyTrackerAuth"]),
    ]
)
