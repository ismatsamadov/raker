// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RakerKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RakerFoundation", targets: ["RakerFoundation"]),
    ],
    targets: [
        // Base and domain
        .target(name: "RakerFoundation"),

        // Tests
        .testTarget(name: "RakerFoundationTests", dependencies: ["RakerFoundation"]),
    ]
)
