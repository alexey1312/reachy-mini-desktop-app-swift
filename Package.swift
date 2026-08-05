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
        .library(name: "HuggingFaceAuth", targets: ["HuggingFaceAuth"]),
        .library(name: "ReachyKit", targets: ["ReachyKit"]),
        .library(name: "ReachyMedia", targets: ["ReachyMedia"]),
        .library(name: "ReachyScene", targets: ["ReachyScene"]),
        .library(name: "ReachyUI", targets: ["ReachyUI"]),
        .library(name: "ReachyWidgetUI", targets: ["ReachyWidgetUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
        .package(url: "https://github.com/stasel/WebRTC.git", from: "150.0.0"),
    ],
    targets: [
        // This app's own Hugging Face session — sign-in, token custody, renewal.
        // Nothing here knows what a robot is: it depends on Foundation, CryptoKit
        // and Security alone, and a target boundary is what keeps it that way.
        // The robot's *own* account (`/api/hf-auth/*`) is a daemon surface and
        // stays in ReachyKit — which does not depend on this target either, so a
        // token reaches it as a value the UI passes in, never as a global.
        .target(name: "HuggingFaceAuth"),
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
            dependencies: ["HuggingFaceAuth", "ReachyKit", "ReachyMedia", "ReachyScene"],
            // `Previews` sits beside the views it documents but is compiled by the Xcode targets
            // in `Apps/`, not by this one: `#Preview` is an external macro whose implementation
            // ships inside Xcode's platform SDKs, so SwiftPM builds on the pinned swift.org
            // toolchain fail with "plugin for module 'PreviewsMacros' not found".
            exclude: ["AGENTS.md", "CLAUDE.md", "Previews"]
        ),
        // The widget's views, deliberately not in ReachyUI: that target links
        // ReachyMedia (WebRTC) and ReachyScene (RealityKit), and a widget
        // extension — woken for a moment, on a hard memory budget — has no
        // business loading a media stack to draw two lines of text.
        .target(
            name: "ReachyWidgetUI",
            dependencies: ["ReachyKit"],
            exclude: ["Previews"]
        ),
        // Not a product: stubs for the test targets only, in a plain target because
        // one test target cannot import another's sources.
        .target(name: "ReachyTestSupport"),
        .testTarget(
            name: "HuggingFaceAuthTests",
            dependencies: ["HuggingFaceAuth", "ReachyTestSupport"]
        ),
        .testTarget(
            name: "ReachyKitTests",
            dependencies: ["ReachyKit", "ReachyTestSupport"],
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
            // `ReachyMedia` for `CameraSession`: the viewport now borrows one from
            // a remote session instead of always building its own, and that
            // ownership is what its tests have to assert on.
            dependencies: ["ReachyUI", "ReachyKit", "ReachyMedia", "HuggingFaceAuth"]
        ),
        .testTarget(
            name: "ReachyWidgetUITests",
            dependencies: ["ReachyWidgetUI", "ReachyKit"]
        ),
    ]
)
