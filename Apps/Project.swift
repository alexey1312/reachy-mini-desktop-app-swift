import ProjectDescription

let project = Project(
    name: "ReachyMiniApps",
    packages: [
        // Local ReachyKit SPM package at the repo root
        .package(path: ".."),
        // Prefire renders SwiftUI previews as snapshots and as a browsable playbook. It is
        // declared here rather than in Package.swift because its generated tests and its
        // PlaybookView both call UIKit unconditionally — the root package still builds for macOS.
        .remote(url: "https://github.com/BarredEwe/Prefire", requirement: .upToNextMajor(from: "5.7.0")),
        .remote(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            requirement: .upToNextMajor(from: "1.19.4")
        ),
    ],
    settings: .settings(configurations: [
        // Set project-wide rather than per target: the previews and the playbook reach ReachyUI's
        // internal screens through `@testable import`, and it is the *package* target that has to
        // be built with testability for that to link.
        .debug(name: .debug, settings: ["ENABLE_TESTABILITY": "YES"]),
        .release(name: .release),
    ]),
    targets: [
        .target(
            name: "ReachySpike",
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "com.alexey1312.ReachyMiniSpike",
            deploymentTargets: .multiplatform(iOS: "18.0", macOS: "15.0"),
            infoPlist: .extendingDefault(with: [
                // Phase 0.4 device checks: Local Network permission + Bonjour + ATS
                "NSLocalNetworkUsageDescription": .string(
                    "Discovers and connects to your Reachy Mini robot on the local network."
                ),
                "NSBonjourServices": .array([
                    .string("_reachy-mini._tcp"),
                    .string("_http._tcp"),
                ]),
                "NSAppTransportSecurity": .dictionary([
                    "NSAllowsLocalNetworking": .boolean(true),
                ]),
                // BLE Wi-Fi provisioning. The only key a foreground central needs on
                // iOS 18: no capability, and no pairing prompt either, since the robot
                // registers a NoInputNoOutput Just-Works agent.
                // NSBluetoothPeripheralUsageDescription is iOS 12 and earlier — omitted.
                "NSBluetoothAlwaysUsageDescription": .string(
                    "Sets up your Reachy Mini's Wi-Fi and recovers a robot that can't reach the network."
                ),
                // Phase 2 camera: WebRTC mic uplink (client mic → robot speaker)
                "NSMicrophoneUsageDescription": .string(
                    "Talk to people near your Reachy Mini through its speaker."
                ),
                "UILaunchScreen": .dictionary([:]),
            ]),
            sources: ["ReachySpike/Sources/**"],
            dependencies: [
                .package(product: "ReachyKit"),
                .package(product: "ReachyUI"),
            ]
        ),
        .target(
            name: "ReachyStorybook",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.alexey1312.ReachyMiniStorybook",
            deploymentTargets: .multiplatform(iOS: "18.0"),
            infoPlist: .extendingDefault(with: [
                // No Bonjour or ATS keys: the storybook renders fixtures and never reaches the network.
                "UILaunchScreen": .dictionary([:]),
            ]),
            // `PrefirePlaybookPlugin` is deliberately absent: it only ever scans the sources of
            // the target it is attached to (`GeneratePlaybookCommand` ignores the config's
            // `sources`, and `playbook_configuration` has no such key), so it cannot see the
            // previews that live in ReachyUI. `mise run storybook` runs the CLI instead.
            // `SpikeView` belongs to ReachySpike, which an app target cannot import; its two
            // source files are compiled in directly so the catalogue can show that screen too.
            sources: [
                "ReachyStorybook/Sources/**",
                "ReachyStorybook/Generated/**",
                "../Sources/ReachyUI/Previews/**",
                "ReachySpike/Sources/SpikeView.swift",
                "ReachySpike/Sources/SpikeModel.swift",
                "ReachySpike/Previews/**",
            ],
            dependencies: [
                .package(product: "ReachyUI"),
                .package(product: "Prefire"),
            ]
        ),
        .target(
            name: "ReachyUISnapshotTests",
            destinations: [.iPhone, .iPad],
            product: .unitTests,
            bundleId: "com.alexey1312.ReachyUISnapshotTests",
            deploymentTargets: .multiplatform(iOS: "18.0"),
            sources: [
                "ReachyUISnapshotTests/Sources/**",
                "../Sources/ReachyUI/Previews/**",
                "ReachySpike/Sources/SpikeView.swift",
                "ReachySpike/Sources/SpikeModel.swift",
                "ReachySpike/Previews/**",
            ],
            dependencies: [
                .package(product: "ReachyUI"),
                .package(product: "Prefire"),
                .package(product: "SnapshotTesting"),
                .package(product: "PrefireTestsPlugin", type: .plugin),
            ]
        ),
    ]
)
