// swift-tools-version:5.9
// For `swift build` / editors. Release builds (universal .app bundle) use ./build.sh.
import PackageDescription

let package = Package(
    name: "BarTidy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BarTidy", path: "Sources/BarTidy")
    ]
)
