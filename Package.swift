// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kundkoll",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Kundkoll",
            path: "Sources/Kundkoll",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
