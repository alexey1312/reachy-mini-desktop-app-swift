import Foundation

/// The daemon's self-update surface.
///
/// Deliberately separate from `RobotAPIClient`: these routes are mounted only when
/// the daemon runs with `--wireless-version`, they sit outside the `/api` prefix, and
/// they are absent from `openapi.json` (the committed spec is generated without that
/// flag), so the generated client cannot reach them. Folding them into the connection
/// surface would also hand every existing test double three more methods to stub.
public protocol DaemonUpdateClient: Sendable {
    func availableUpdate(preRelease: Bool) async throws -> DaemonUpdateAvailability
    /// Returns the job id to follow over `UpdateLogStreamClient`.
    func startUpdate(preRelease: Bool) async throws -> String
    func updateInfo(jobID: String) async throws -> DaemonUpdateJob
}

/// Defaults keep test doubles focused on the behaviour they exercise.
public extension DaemonUpdateClient {
    func availableUpdate(preRelease _: Bool) async throws -> DaemonUpdateAvailability {
        throw URLError(.unsupportedURL)
    }

    func startUpdate(preRelease _: Bool) async throws -> String {
        throw URLError(.unsupportedURL)
    }

    func updateInfo(jobID _: String) async throws -> DaemonUpdateJob {
        throw URLError(.unsupportedURL)
    }
}
