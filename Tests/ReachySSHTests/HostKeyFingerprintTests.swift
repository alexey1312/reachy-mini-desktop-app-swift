import Foundation
@testable import ReachySSH
import Testing

/// The vectors come from `ssh-keygen -lf` on freshly generated keys, not from this
/// code — checking a fingerprint against the implementation that produced it proves
/// nothing.
@Suite("Host key fingerprints")
struct HostKeyFingerprintTests {
    static let ed25519 =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKxSnnReKXYSkOtrc1X2t3KlT7aQiTAgRxF4A+fDZCz"
    static let ed25519Fingerprint = "SHA256:8c+THyRN31QyZOA24zAV81rvVwuLfxsMzdlUNbT8Jzo"

    static let ecdsa =
        // swiftlint:disable:next line_length
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOd1Bvm7mJHkOBy3mwgfQgJfhM1H1yc7OSwU9wBbe6kADDBL+lrQDy6gQYbUcDEy3u9toj9LO4G4ejlikUDOtFk="
    static let ecdsaFingerprint = "SHA256:+d5x7swpcDgSiS1EnPib85Ues7kud5XKZW16NcDT0s0"

    @Test("matches ssh-keygen for an Ed25519 key")
    func ed25519MatchesSSHKeygen() throws {
        let fingerprint = try #require(HostKeyFingerprint(openSSHPublicKey: Self.ed25519))
        #expect(fingerprint.sha256 == Self.ed25519Fingerprint)
        #expect(fingerprint.algorithm == "ssh-ed25519")
    }

    @Test("matches ssh-keygen for an ECDSA key")
    func ecdsaMatchesSSHKeygen() throws {
        let fingerprint = try #require(HostKeyFingerprint(openSSHPublicKey: Self.ecdsa))
        #expect(fingerprint.sha256 == Self.ecdsaFingerprint)
        #expect(fingerprint.algorithm == "ecdsa-sha2-nistp256")
    }

    @Test("drops the comment so one key cannot pin as two")
    func commentIsNotPartOfIdentity() throws {
        let bare = try #require(HostKeyFingerprint(openSSHPublicKey: Self.ed25519))
        let commented = try #require(
            HostKeyFingerprint(openSSHPublicKey: Self.ed25519 + " pollen@reachy-mini")
        )
        #expect(bare == commented)
        #expect(commented.openSSHPublicKey == Self.ed25519)
    }

    @Test("tolerates the trailing newline a .pub file carries")
    func trailingNewline() throws {
        let fingerprint = try #require(HostKeyFingerprint(openSSHPublicKey: Self.ed25519 + "\n"))
        #expect(fingerprint.sha256 == Self.ed25519Fingerprint)
    }

    @Test(
        "refuses anything that is not an OpenSSH public key",
        arguments: ["", "ssh-ed25519", "ssh-ed25519 not-base64!!", "   "]
    )
    func rejectsMalformed(_ input: String) {
        #expect(HostKeyFingerprint(openSSHPublicKey: input) == nil)
    }

    @Test("groups the digest for reading aloud without changing it")
    func groupedForDisplay() throws {
        let fingerprint = try #require(HostKeyFingerprint(openSSHPublicKey: Self.ed25519))
        let grouped = fingerprint.groupedForDisplay
        #expect(grouped.hasPrefix("SHA256:"))
        #expect(grouped.replacingOccurrences(of: " ", with: "") == fingerprint.sha256)
    }
}
