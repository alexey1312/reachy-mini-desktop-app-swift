// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ReachyMini",
    platforms: [
        // RealityView (the 3D robot viewer) is iOS 18 / macOS 15.
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "ReachyKit", targets: ["ReachyKit"]),
        .library(name: "ReachyMedia", targets: ["ReachyMedia"]),
        .library(name: "ReachyScene", targets: ["ReachyScene"]),
        .library(name: "ReachyUI", targets: ["ReachyUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
        .package(url: "https://github.com/stasel/WebRTC.git", from: "150.0.0"),
    ],
    targets: [
        .target(
            name: "ReachyKit",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            exclude: ["AGENTS.md", "CLAUDE.md"],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .target(
            name: "ReachyMedia",
            dependencies: [
                "ReachyKit",
                .product(name: "WebRTC", package: "WebRTC"),
            ]
        ),
        .target(
            name: "ReachyScene",
            dependencies: ["ReachyKit"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "ReachyUI",
            dependencies: ["ReachyKit", "ReachyMedia", "ReachyScene"],
            // `Previews` sits beside the views it documents but is compiled by the Xcode targets
            // in `Apps/`, not by this one: `#Preview` is an external macro whose implementation
            // ships inside Xcode's platform SDKs, so SwiftPM builds on the pinned swift.org
            // toolchain fail with "plugin for module 'PreviewsMacros' not found".
            exclude: ["AGENTS.md", "CLAUDE.md", "Previews"]
        ),
        .testTarget(
            name: "ReachyKitTests",
            dependencies: ["ReachyKit"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "ReachySceneTests",
            dependencies: ["ReachyScene", "ReachyKit"]
        ),
        .testTarget(
            name: "ReachyUITests",
            dependencies: ["ReachyUI", "ReachyKit"]
        ),
    ]
)
