import CryptoKit
import Foundation

/// Seals a Wi-Fi password so it never crosses Bluetooth in the clear.
///
/// Mirrors the daemon's `x25519-hkdf-sha256-aesgcm` scheme byte for byte — salt, info
/// label and AAD all take part in the key, so any drift fails as an authentication
/// error rather than as garbage.
///
/// **Known limitation, inherited from upstream and documented there.** This protects
/// the password from a passive listener, but not from an active man-in-the-middle
/// present during the few seconds of setup: it would answer the key exchange with its
/// own public key and could then brute-force the 5-character PIN offline. Upstream
/// tracks a PAKE as the fix. Provisioning should happen somewhere the user trusts.
public enum WiFiPasswordSeal {
    /// Byte-for-byte identical to the daemon's HKDF `info`.
    static let info = Data("reachy-mini-wifi-psk-v1".utf8)

    public enum Failure: Error, Equatable {
        case malformedRobotKey
        case unsupportedAlgorithm(String)
    }

    /// `ephemeralPrivateKey` and `nonce` exist only so a test can reproduce a known
    /// ciphertext. Production always takes the random defaults.
    public static func seal(
        ssid: String,
        password: String,
        pin: String,
        key: WiFiProvisioningKey,
        ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey = .init(),
        nonce: AES.GCM.Nonce? = nil
    ) throws -> SealedWiFiCredentials {
        guard key.alg == WiFiProvisioningKey.supportedAlgorithm else {
            throw Failure.unsupportedAlgorithm(key.alg)
        }
        guard let raw = Data(base64Encoded: key.pk),
              let robotPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
        else {
            throw Failure.malformedRobotKey
        }

        let shared = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: robotPublicKey)
        // The PIN is the HKDF salt: knowing the key exchange alone is not enough to
        // open the password.
        let symmetricKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(pin.utf8),
            sharedInfo: info,
            outputByteCount: 32
        )

        // The SSID as AAD binds the sealed password to its target network, so a
        // captured blob cannot be replayed against a different one.
        let sealed = try AES.GCM.seal(
            Data(password.utf8),
            using: symmetricKey,
            nonce: nonce,
            authenticating: Data(ssid.utf8)
        )

        return SealedWiFiCredentials(
            ssid: ssid,
            kid: key.kid,
            epk: ephemeralPrivateKey.publicKey.rawRepresentation.base64EncodedString(),
            nonce: Data(sealed.nonce).base64EncodedString(),
            ct: (sealed.ciphertext + sealed.tag).base64EncodedString()
        )
    }
}
