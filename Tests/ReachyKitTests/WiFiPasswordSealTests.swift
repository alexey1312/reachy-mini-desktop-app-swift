import CryptoKit
import Foundation
@testable import ReachyKit
import Testing

/// The sealed password is the one thing here with no feedback loop: if the derivation
/// drifts by a byte the robot answers `ERROR: Bad credentials (wrong PIN?)`, which
/// reads exactly like the user mistyping the PIN. So it is pinned against a vector
/// produced by the *daemon's* library — see `Scripts/generate-seal-fixture.py`.
@Suite("WiFiPasswordSeal")
struct WiFiPasswordSealTests {
    private struct Vector: Decodable {
        let ssid: String
        let password: String
        let pin: String
        let kid: String
        let robotPublicKey: String
        let clientPrivateKey: String
        let nonce: String
        let expectedClientPublicKey: String
        let expectedCiphertext: String
    }

    private func loadVector() throws -> Vector {
        let url = try #require(Bundle.module.url(
            forResource: "wifi_seal_vector",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
    }

    private func seal(_ vector: Vector, ssid: String? = nil) throws -> SealedWiFiCredentials {
        try WiFiPasswordSeal.seal(
            ssid: ssid ?? vector.ssid,
            password: vector.password,
            pin: vector.pin,
            key: WiFiProvisioningKey(kid: vector.kid, pk: vector.robotPublicKey),
            ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: #require(Data(base64Encoded: vector.clientPrivateKey))
            ),
            nonce: AES.GCM.Nonce(data: #require(Data(base64Encoded: vector.nonce)))
        )
    }

    @Test("reproduces a ciphertext the daemon's own library produced")
    func matchesTheKnownAnswer() throws {
        let vector = try loadVector()

        let sealed = try seal(vector)

        #expect(sealed.epk == vector.expectedClientPublicKey)
        #expect(sealed.nonce == vector.nonce)
        #expect(sealed.ct == vector.expectedCiphertext)
        #expect(sealed.ssid == vector.ssid)
        #expect(sealed.kid == vector.kid)
    }

    @Test("the tag is appended to the ciphertext, which CryptoKit keeps separate")
    func appendsTheAuthenticationTag() throws {
        let vector = try loadVector()

        let sealed = try seal(vector)
        let raw = try #require(Data(base64Encoded: sealed.ct))

        #expect(raw.count == vector.password.utf8.count + 16)
    }

    @Test("base64 is standard, not URL-safe — the daemon decodes with b64decode")
    func usesStandardBase64() throws {
        let vector = try loadVector()

        let sealed = try seal(vector)

        for field in [sealed.epk, sealed.nonce, sealed.ct] {
            #expect(!field.contains("-"))
            #expect(!field.contains("_"))
            #expect(Data(base64Encoded: field) != nil)
        }
    }

    @Test("the SSID is bound into the ciphertext, so a captured blob can't target another network")
    func bindsTheSSIDAsAAD() throws {
        let vector = try loadVector()

        let sealed = try seal(vector)
        let other = try seal(vector, ssid: "Someone Else's Net")

        #expect(sealed.ct != other.ct)
    }

    @Test("a robot key that is not a 32-byte X25519 point is rejected before anything is sent")
    func rejectsAMalformedRobotKey() {
        #expect(throws: WiFiPasswordSeal.Failure.malformedRobotKey) {
            try WiFiPasswordSeal.seal(
                ssid: "net",
                password: "pw",
                pin: "12345",
                key: WiFiProvisioningKey(kid: "k", pk: "not base64 at all")
            )
        }
        #expect(throws: WiFiPasswordSeal.Failure.malformedRobotKey) {
            try WiFiPasswordSeal.seal(
                ssid: "net",
                password: "pw",
                pin: "12345",
                key: WiFiProvisioningKey(kid: "k", pk: Data(repeating: 0x41, count: 16).base64EncodedString())
            )
        }
    }

    @Test("an algorithm this client does not implement is refused rather than guessed at")
    func rejectsAnUnknownAlgorithm() throws {
        let vector = try loadVector()

        #expect(throws: WiFiPasswordSeal.Failure.unsupportedAlgorithm("kyber-something")) {
            try WiFiPasswordSeal.seal(
                ssid: vector.ssid,
                password: vector.password,
                pin: vector.pin,
                key: WiFiProvisioningKey(kid: vector.kid, pk: vector.robotPublicKey, alg: "kyber-something")
            )
        }
    }

    /// RFC 5869 test case 1. If CryptoKit's HKDF ever changes shape this fails by
    /// name, instead of surfacing as an unexplained ciphertext mismatch above.
    @Test("CryptoKit's HKDF still matches RFC 5869")
    func hkdfMatchesTheStandard() {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(repeating: 0x0B, count: 22)),
            salt: Data((0x00 ... 0x0C).map(UInt8.init)),
            info: Data((0xF0 ... 0xF9).map(UInt8.init)),
            outputByteCount: 42
        )
        let expected = """
        3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865
        """

        let hex = derived.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        #expect(hex == expected)
    }
}
