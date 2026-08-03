// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ReachyMini",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ReachyKit", targets: ["ReachyKit"]),
        .library(name: "ReachyUI", targets: ["ReachyUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
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
            name: "ReachyUI",
            dependencies: ["ReachyKit"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .testTarget(
            name: "ReachyKitTests",
            dependencies: ["ReachyKit"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "ReachyUITests",
            dependencies: ["ReachyUI", "ReachyKit"]
        ),
    ]
)
