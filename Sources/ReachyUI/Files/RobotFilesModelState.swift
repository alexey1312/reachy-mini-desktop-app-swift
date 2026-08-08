import Foundation
import ReachySSH

/// The vocabulary the files screen switches on, and the one derived value that
/// reads state without writing any.
///
/// Split from `RobotFilesModel.swift` to keep it under SwiftLint's 400-line limit.
/// What could *not* move is anything that writes a `private(set)` member — the
/// setter is private to the declaring file, which is also why the `#if DEBUG`
/// preview factory has to stay there (`ReachyUI/AGENTS.md`).
@MainActor
extension RobotFilesModel {
    /// Where the session is, as opposed to what a single operation did.
    enum Phase: Equatable {
        /// Nothing asked yet.
        case idle
        /// No password stored for this robot, or the stored one was refused.
        case needsPassword
        /// First contact. The user has to see this key before it is pinned.
        case confirmHostKey(HostKeyFingerprint)
        /// A pinned robot answered with a different key. Never auto-accepted.
        case hostKeyChanged(pinned: HostKeyFingerprint, offered: HostKeyFingerprint)
        case connecting
        case browsing
        case failed(String)
    }

    /// A destructive action waiting for a confirmation dialog.
    enum Confirmation: Equatable, Identifiable {
        case delete(RemoteFile)

        var id: String {
            switch self {
            case let .delete(file): "delete-\(file.path)"
            }
        }
    }

    /// Deepest first, so the trail reads left to right.
    var breadcrumb: [(name: String, path: String)] {
        var trail = [(name: "/", path: "/")]
        var walked = ""
        for component in path.split(separator: "/") {
            walked += "/" + component
            trail.append((name: String(component), path: walked))
        }
        return trail
    }
}
