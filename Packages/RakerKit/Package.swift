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
        .library(name: "SpaceIndex", targets: ["SpaceIndex"]),
        .library(name: "ScanEngine", targets: ["ScanEngine"]),
        .executable(name: "raker", targets: ["RakerCLI"]),
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

        // Engines
        .target(name: "SpaceIndex", dependencies: ["RakerFoundation", "RakerModel", "FileSystemKit"]),
        .target(name: "ScanEngine", dependencies: ["RakerFoundation", "RakerModel", "FileSystemKit", "SpaceIndex"]),

        // Shells
        .executableTarget(
            name: "RakerCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "RakerFoundation", "RakerModel", "SafetyPolicy", "FileSystemKit", "SpaceIndex", "ScanEngine",
            ]
        ),

        // Tests
        .testTarget(name: "RakerFoundationTests", dependencies: ["RakerFoundation"]),
        .testTarget(name: "SafetyPolicyTests", dependencies: ["SafetyPolicy"]),
        .testTarget(name: "FileSystemKitTests", dependencies: ["FileSystemKit", "RakerFoundation"]),
        .testTarget(name: "ScanEngineTests", dependencies: ["ScanEngine", "SpaceIndex", "FileSystemKit"]),
    ]
)
