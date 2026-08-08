import CryptoKit
import Foundation

/// An SSH host key, in the form a user can compare against `ssh-keygen -lf`.
///
/// Built from the OpenSSH text form rather than from a `NIOSSHPublicKey`, and that
/// is what keeps this type — and its tests — free of SwiftNIO. The base64 field of
/// `"ssh-ed25519 AAAAC3Nza…"` *is* the SSH wire encoding of the key, which is
/// exactly what OpenSSH hashes to print a fingerprint. So the whole computation is
/// Foundation plus one SHA-256.
public struct HostKeyFingerprint: Hashable, Sendable {
    /// The full `"<algorithm> <base64>"` line, which is what gets pinned: a text
    /// round-trip through `NIOSSHPublicKey(openSSHPublicKey:)` beats storing an
    /// opaque blob whose layout belongs to a dependency.
    public let openSSHPublicKey: String
    /// `ssh-ed25519`, `ecdsa-sha2-nistp256`, and so on.
    public let algorithm: String
    /// `SHA256:` followed by unpadded base64, the way OpenSSH 6.8+ prints it.
    public let sha256: String

    public init?(openSSHPublicKey: String) {
        let line = openSSHPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count >= 2, let wire = Data(base64Encoded: String(fields[1])) else { return nil }
        // Keep only algorithm and key: an `authorized_keys`-style comment is not
        // part of the identity and would make two pins of one key.
        self.openSSHPublicKey = "\(fields[0]) \(fields[1])"
        algorithm = String(fields[0])
        let digest = Data(SHA256.hash(data: wire)).base64EncodedString()
        sha256 = "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
    }

    /// Grouped for reading aloud over a desk, which is the whole point of showing
    /// it. The `SHA256:` prefix stays attached to the first group.
    public var groupedForDisplay: String {
        let body = sha256.dropFirst("SHA256:".count)
        let groups = stride(from: 0, to: body.count, by: 11).map { offset -> String in
            let start = body.index(body.startIndex, offsetBy: offset)
            let end = body.index(start, offsetBy: min(11, body.count - offset))
            return String(body[start ..< end])
        }
        return "SHA256:" + groups.joined(separator: " ")
    }
}
