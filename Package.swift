// swift-tools-version: 5.9
import PackageDescription

// Built as a plain SwiftPM executable and wrapped into an .app bundle by
// build.sh for direct distribution with Command Line Tools. The separate
// TokensOnTrack.xcodeproj uses these same sources for the sandboxed Store app.
let package = Package(
    name: "AIUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AIUsage", path: "Sources/AIUsage")
    ]
)
