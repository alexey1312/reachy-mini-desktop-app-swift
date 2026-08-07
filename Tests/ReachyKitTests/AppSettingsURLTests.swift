import Foundation
@testable import ReachyKit
import Testing

@MainActor
@Suite("An app's own settings page")
struct AppSettingsURLTests {
    /// The robot's host, the app's port — the same split `conversationTurns(for:)`
    /// makes, and for the same reason: `custom_app_url`'s host is `0.0.0.0`, which
    /// dialled from a phone is the phone.
    ///
    /// The app here is deliberately **not** on 7860, so a version that ignored the
    /// declared port and hardcoded the default could not pass this.
    @Test("keeps the robot's host and takes only the app's port")
    func combinesRobotHostWithAppPort() {
        let session = RobotSession.preview(address: RobotAddress(host: "reachy-mini.local", port: 8000))
        let app = RobotApp.preview(
            name: "reachy_mini_conversation_app",
            installed: true,
            customAppURL: "http://0.0.0.0:8123/"
        )

        #expect(session.appSettingsURL(for: app)?.absoluteString == "http://reachy-mini.local:8123/")
    }

    /// Bracketed, because `URLComponents` rejects a bare IPv6 literal in `host`
    /// (project rule 5, and upstream issue #269 was exactly this).
    @Test("brackets an IPv6 robot")
    func bracketsIPv6() {
        let session = RobotSession.preview(address: RobotAddress(host: "fd00::1", port: 8000))
        let app = RobotApp.preview(
            name: "reachy_mini_conversation_app",
            installed: true,
            customAppURL: "http://0.0.0.0:7860/"
        )

        #expect(session.appSettingsURL(for: app)?.absoluteString == "http://[fd00::1]:7860/")
    }

    /// **No fallback to 7860 here**, unlike `ConversationRPCClient`. That one is a
    /// background stream whose failure nobody sees; this one becomes a row someone
    /// taps, and a row leading to a port nothing listens on is worse than no row.
    /// The absent key is the daemon's only signal that an app serves no page.
    @Test("offers nothing for an app that declared no port", arguments: [
        nil,
        "http://0.0.0.0",
        "",
    ] as [String?])
    func requiresADeclaredPort(customAppURL: String?) {
        let session = RobotSession.preview()
        let app = RobotApp.preview(
            name: "reachy_mini_dance",
            installed: true,
            customAppURL: customAppURL
        )

        #expect(session.appSettingsURL(for: app) == nil)
    }

    /// The page is served by the app process on the robot's own network, and the
    /// relay does not carry it — the same boundary that leaves
    /// `RunningAppModel.conversationStreamKey` nil over a remote session.
    @Test("offers nothing over a relay session")
    func requiresALANAddress() {
        let session = RobotSession.preview(link: .remote)
        let app = RobotApp.preview(
            name: "reachy_mini_conversation_app",
            installed: true,
            customAppURL: "http://0.0.0.0:7860/"
        )

        #expect(session.appSettingsURL(for: app) == nil)
    }
}
