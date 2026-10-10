// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Baba",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Baba",
            path: "Sources/Baba",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
