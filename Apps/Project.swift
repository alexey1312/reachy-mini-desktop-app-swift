import ProjectDescription

let project = Project(
    name: "ReachyMiniApps",
    packages: [
        // Local ReachyKit SPM package at the repo root
        .package(path: ".."),
    ],
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
    ]
)
