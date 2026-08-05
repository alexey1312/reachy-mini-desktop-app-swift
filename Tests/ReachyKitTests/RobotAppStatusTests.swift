import Foundation
@testable import ReachyKit
import Testing

@Suite("Robot app status")
struct RobotAppStatusTests {
    private func status(_ json: String) throws -> RobotAppStatus {
        try JSONDecoder().decode(RobotAppStatus.self, from: Data(json.utf8))
    }

    private func running(state: String) -> String {
        #"""
        {
          "info": {"name": "dance", "source_kind": "installed", "extra": {"id": "pollen-robotics/dance"}},
          "state": "\#(state)"
        }
        """#
    }

    @Test("reads the app and its state")
    func decodesRunningApp() throws {
        let status = try status(running(state: "running"))
        #expect(status.app.spaceID == "pollen-robotics/dance")
        #expect(status.state == .running)
        #expect(status.isBusy)
        #expect(status.error == nil)
    }

    /// The daemon versions independently of this client, so a state it grows later
    /// must read as "something is running", never as a decoding failure.
    @Test("an unfamiliar state is carried, not thrown")
    func toleratesUnknownState() throws {
        let status = try status(running(state: "restarting"))
        #expect(status.state == .unknown("restarting"))
        #expect(status.isBusy)
    }

    @Test("a crashed app reports why")
    func decodesError() throws {
        let status = try status(#"""
        {
          "info": {"name": "dance", "source_kind": "installed"},
          "state": "error",
          "error": "ModuleNotFoundError: no module named 'reachy_mini'"
        }
        """#)
        #expect(status.state == .error)
        #expect(status.isBusy == false)
        #expect(status.error?.hasPrefix("ModuleNotFoundError") == true)
    }
}

@Suite("Robot app lock")
struct RobotAppLockStatusTests {
    private func lock(_ json: String) throws -> RobotAppLockStatus {
        try JSONDecoder().decode(RobotAppLockStatus.self, from: Data(json.utf8))
    }

    @Test("a free robot has no holder")
    func decodesFree() throws {
        let status = try lock(#"{"state": "free"}"#)
        #expect(status.state == .free)
        #expect(status.holderName == nil)
        #expect(status.isHeld == false)
    }

    /// Someone driving the robot from the Hugging Face relay holds the same lock a
    /// local app does — the screen has to tell the two apart to explain itself.
    @Test("a remote session names its holder")
    func decodesRemoteSession() throws {
        let status = try lock(#"{"state": "remote_session", "holder_name": "alexey1312"}"#)
        #expect(status.state == .remoteSession)
        #expect(status.holderName == "alexey1312")
        #expect(status.isHeld)
    }

    @Test("an unfamiliar lock state still counts as held")
    func toleratesUnknownState() throws {
        let status = try lock(#"{"state": "maintenance"}"#)
        #expect(status.state == .unknown("maintenance"))
        #expect(status.isHeld)
    }
}

@Suite("App updates")
struct AppUpdatesSummaryTests {
    private static let response = #"""
    {
      "apps_with_updates": [
        {
          "app_name": "dance_party",
          "space_id": "pollen-robotics/reachy-mini-dance",
          "installed_sha": "abc",
          "latest_sha": "def",
          "update_available": true,
          "last_modified": "2026-07-01T10:00:00.000Z"
        }
      ],
      "apps_checked": 3,
      "apps_skipped": 1
    }
    """#

    private func summary() throws -> AppUpdatesSummary {
        try AppUpdatesSummary(
            JSONDecoder().decode(Components.Schemas.AppUpdatesResponse.self, from: Data(Self.response.utf8))
        )
    }

    @Test("counts what the daemon could and could not check")
    func decodesCounts() throws {
        let summary = try summary()
        #expect(summary.checked == 3)
        #expect(summary.skipped == 1)
    }

    /// The daemon reports updates under the *installed* name, which is the entry
    /// point's, while the catalogue knows the app by its Space — so both keys have
    /// to answer.
    @Test("finds the update by either name the app goes under")
    func matchesByNameOrSpace() throws {
        let summary = try summary()
        let installed = try JSONDecoder().decode(RobotApp.self, from: Data(#"""
        {"name": "dance_party", "source_kind": "installed", "extra": {}}
        """#.utf8))
        let catalogue = try JSONDecoder().decode(RobotApp.self, from: Data(#"""
        {"name": "reachy-mini-dance", "source_kind": "hf_space",
         "extra": {"id": "pollen-robotics/reachy-mini-dance"}}
        """#.utf8))
        let other = try JSONDecoder().decode(RobotApp.self, from: Data(#"""
        {"name": "chess", "source_kind": "installed", "extra": {}}
        """#.utf8))

        #expect(summary.hasUpdate(for: installed))
        #expect(summary.hasUpdate(for: catalogue))
        #expect(summary.hasUpdate(for: other) == false)
    }
}
