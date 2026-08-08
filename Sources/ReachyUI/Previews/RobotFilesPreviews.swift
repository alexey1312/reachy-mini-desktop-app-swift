import ReachySSH
@testable import ReachyUI
import SwiftUI

// The robot's own file system over SFTP — the one screen that reaches the robot
// without the daemon, because the daemon has no route that writes a file.
//
// The fixture is the 2026-08-07 incident: `user_personalities/Test_Ru` left in the
// old four-file format with no `profile.md`, which is what made the conversation app
// exit 1 before it could serve the settings page that would have fixed it.

// MARK: - Getting in

#Preview("Robot files — password") {
    PreviewScene.robotFiles(.preview(phase: .needsPassword, password: ""))
}

// A refused password goes back to the field rather than to a dead end, and the
// stored one is dropped — keeping it means the next visit fails identically.
#Preview("Robot files — password refused") {
    PreviewScene.robotFiles(
        .preview(
            phase: .needsPassword,
            error: "That password was refused by the robot.",
            password: ""
        )
    )
}

// Trust on first use. The key is shown before it is pinned, because pinning it
// silently would make the pin worthless.
#Preview("Robot files — new robot") {
    PreviewScene.robotFiles(.preview(phase: .confirmHostKey(.previewEd25519)))
}

// The serious one: a robot that was pinned answered with a different key. Reflashing
// does this — and so does someone sitting in the middle.
#Preview("Robot files — identity changed") {
    PreviewScene.robotFiles(
        .preview(phase: .hostKeyChanged(pinned: .previewEd25519, offered: .previewECDSA))
    )
}

// MARK: - Browsing

#Preview("Robot files — app package") {
    PreviewScene.robotFiles(.preview(entries: RobotFilesModel.previewEntries()))
}

// The directory the incident lived in. Four old-format files and no `profile.md`.
#Preview("Robot files — broken personality") {
    let personalities = RemoteFile.joining(PreviewFileSystem.appPackage, "user_personalities")
    let profile = RemoteFile.joining(personalities, "Test_Ru")
    return PreviewScene.robotFiles(
        .preview(path: profile, entries: RobotFilesModel.previewEntries(at: profile))
    )
}

#Preview("Robot files — empty folder") {
    PreviewScene.robotFiles(.preview(path: "/home/pollen", entries: []))
}

// Never answered, as opposed to answered with nothing — without the distinction the
// first frame would claim an empty folder before anything had been asked.
#Preview("Robot files — reading") {
    PreviewScene.robotFiles(.preview(entries: [], hasListed: false))
}

#Preview("Robot files — transferring") {
    PreviewScene.robotFiles(
        .preview(entries: RobotFilesModel.previewEntries(), transferring: "profile.md")
    )
}

// MARK: - Refusals

// A read cap rather than a growing buffer: a phone must not pull a model file into
// memory to hand it to a document picker.
#Preview("Robot files — file too large") {
    PreviewScene.robotFiles(
        .preview(
            entries: RobotFilesModel.previewEntries(),
            error: "That file is 2.1 GB. This screen opens files up to 8 MB."
        )
    )
}

// `rmdir` refuses a directory with contents. The server's refusal is the guard —
// nothing here recurses.
#Preview("Robot files — folder not empty") {
    PreviewScene.robotFiles(
        .preview(
            entries: RobotFilesModel.previewEntries(),
            error: "That folder is not empty. Empty it first."
        )
    )
}

#Preview("Robot files — permission refused") {
    PreviewScene.robotFiles(
        .preview(
            path: "/root",
            entries: [],
            error: "The robot refused permission. Permission denied"
        )
    )
}

#Preview("Robot files — unreachable") {
    PreviewScene.robotFiles(.preview(phase: .failed("Connection refused. Is SSH enabled on the robot?")))
}

// MARK: - Fixtures

/// Real keys, so the fingerprints in the references are the ones `ssh-keygen -lf`
/// would print rather than plausible-looking noise.
extension HostKeyFingerprint {
    static let previewEd25519 = HostKeyFingerprint(
        openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKxSnnReKXYSkOtrc1X2t3KlT7aQiTAgRxF4A+fDZCz"
    )!

    static let previewECDSA = HostKeyFingerprint(
        openSSHPublicKey:
        // swiftlint:disable:next line_length
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOd1Bvm7mJHkOBy3mwgfQgJfhM1H1yc7OSwU9wBbe6kADDBL+lrQDy6gQYbUcDEy3u9toj9LO4G4ejlikUDOtFk="
    )!
}
