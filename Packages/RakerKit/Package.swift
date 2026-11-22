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

        // Tests
        .testTarget(name: "RakerFoundationTests", dependencies: ["RakerFoundation"]),
        .testTarget(name: "SafetyPolicyTests", dependencies: ["SafetyPolicy"]),
        .testTarget(name: "FileSystemKitTests", dependencies: ["FileSystemKit", "RakerFoundation"]),
        .testTarget(name: "ScanEngineTests", dependencies: ["ScanEngine", "SpaceIndex", "FileSystemKit"]),
    ]
)
