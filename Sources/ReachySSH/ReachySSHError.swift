import Foundation

/// Everything this module can fail with.
///
/// No `LocalizedError`: the sentence a user reads is chosen by the screen that
/// asked, in its own language catalogue, the way `RunningAppCaption` maps a daemon
/// process state rather than letting the domain carry words.
public enum ReachySSHError: Error, Equatable, Sendable {
    case notConnected
    /// First contact with this robot. Carries the key to show and then pin.
    case hostKeyUnknown(HostKeyFingerprint)
    /// A pinned robot answered with a different key. Either the robot was
    /// reflashed, or something is sitting in the middle.
    case hostKeyChanged(pinned: HostKeyFingerprint, offered: HostKeyFingerprint)
    case authenticationFailed
    case pathNotFound(String)
    case notPermitted(String)
    /// `rmdir` on a directory with contents. The server refuses; we do not recurse.
    case directoryNotEmpty(String)
    /// A phone must not pull a multi-gigabyte model file into memory to show it.
    case fileTooLarge(bytes: UInt64, limit: Int)
    /// Anything the SSH or SFTP layer reported that has no case of its own. The
    /// string is the server's or the library's, so it stays a `String`.
    case transport(String)
    case keychain(OSStatus)

    /// Whether retrying with the same inputs could plausibly succeed. A wrong
    /// password or a missing path will not fix itself; a dropped channel might.
    public var isRetryable: Bool {
        switch self {
        case .notConnected, .transport: true
        case .hostKeyUnknown, .hostKeyChanged, .authenticationFailed, .pathNotFound,
             .notPermitted, .directoryNotEmpty, .fileTooLarge, .keychain: false
        }
    }
}
