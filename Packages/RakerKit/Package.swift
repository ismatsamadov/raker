// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RakerKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RakerFoundation", targets: ["RakerFoundation"]),
        .library(name: "RakerModel", targets: ["RakerModel"]),
        .library(name: "SafetyPolicy", targets: ["SafetyPolicy"]),
        .library(name: "FileSystemKit", targets: ["FileSystemKit"]),
        .library(name: "SystemKit", targets: ["SystemKit"]),
        .library(name: "RuleEngine", targets: ["RuleEngine"]),
        .library(name: "SpaceIndex", targets: ["SpaceIndex"]),
        .library(name: "ScanEngine", targets: ["ScanEngine"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "VisualizationKit", targets: ["VisualizationKit"]),
        .library(name: "AppShell", targets: ["AppShell"]),
        .executable(name: "raker", targets: ["RakerCLI"]),
        .executable(name: "RakerDevApp", targets: ["RakerDevApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Base and domain
        .target(name: "RakerFoundation"),
        .target(name: "RakerModel", dependencies: ["RakerFoundation"]),
        .target(name: "SafetyPolicy"),

        // Platform adapters
        .target(name: "FileSystemKit", dependencies: ["RakerFoundation", "RakerModel"]),
        .target(name: "SystemKit", dependencies: ["RakerModel"]),

        // Engines
        .target(name: "RuleEngine", dependencies: ["RakerFoundation", "RakerModel", "SafetyPolicy"]),
        .target(name: "SpaceIndex", dependencies: ["RakerFoundation", "RakerModel", "FileSystemKit"]),
        .target(name: "ScanEngine", dependencies: ["RakerFoundation", "RakerModel", "FileSystemKit", "SpaceIndex"]),

        // Presentation
        .target(name: "DesignSystem", dependencies: ["RakerFoundation"]),
        .target(name: "VisualizationKit", dependencies: ["DesignSystem"]),
        .target(
            name: "AppShell",
            dependencies: [
                "RakerFoundation", "RakerModel", "FileSystemKit", "SpaceIndex", "ScanEngine",
                "DesignSystem", "VisualizationKit",
            ]
        ),

        // Shells
        .executableTarget(
            name: "RakerCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "RakerFoundation", "RakerModel", "SafetyPolicy", "FileSystemKit", "SpaceIndex", "ScanEngine",
            ]
        ),
        // Runs the SwiftUI shell without an Xcode project; the Xcode app target replaces it later.
        .executableTarget(name: "RakerDevApp", dependencies: ["AppShell"]),

        // Tests
        .testTarget(name: "RakerFoundationTests", dependencies: ["RakerFoundation"]),
        .testTarget(name: "SafetyPolicyTests", dependencies: ["SafetyPolicy"]),
        .testTarget(name: "FileSystemKitTests", dependencies: ["FileSystemKit", "RakerFoundation"]),
        .testTarget(name: "RuleEngineTests", dependencies: ["RuleEngine", "RakerModel"]),
        .testTarget(name: "ScanEngineTests", dependencies: ["ScanEngine", "SpaceIndex", "FileSystemKit"]),
        .testTarget(name: "VisualizationKitTests", dependencies: ["VisualizationKit"]),
    ]
)
