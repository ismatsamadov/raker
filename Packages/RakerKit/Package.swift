// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RakerKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RakerFoundation", targets: ["RakerFoundation"]),
        .library(name: "RakerModel", targets: ["RakerModel"]),
        .library(name: "SafetyPolicy", targets: ["SafetyPolicy"]),
    ],
    targets: [
        // Base and domain
        .target(name: "RakerFoundation"),
        .target(name: "RakerModel", dependencies: ["RakerFoundation"]),
        .target(name: "SafetyPolicy"),

        // Tests
        .testTarget(name: "RakerFoundationTests", dependencies: ["RakerFoundation"]),
        .testTarget(name: "SafetyPolicyTests", dependencies: ["SafetyPolicy"]),
    ]
)
