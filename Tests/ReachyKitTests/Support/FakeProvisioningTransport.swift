import CryptoKit
import Foundation
@testable import ReachyKit

/// A robot that answers the provisioning protocol, with the two things worth scripting:
/// how many times it refuses the sealed payload, and when it admits to being on the
/// network. Its keys are real X25519 keys, so the sealing runs for real.
final class FakeProvisioningTransport: WiFiProvisioningTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var issued: [WiFiProvisioningKey] = []
    private var accepted: [SealedWiFiCredentials] = []
    private var refusals = 0
    private var statusReads = 0

    /// Refuses this many sealed payloads with bad credentials before accepting one.
    var refusesFirst = 0
    /// The raw `WIFI_SCAN` reply, truncation and all.
    var scanReply = "[]"
    /// Reports `CONNECTED` once this many status reads have happened.
    var connectsAfterReads = Int.max

    var issuedKeys: [WiFiProvisioningKey] {
        lock.withLock { issued }
    }

    var sealedPayloads: [SealedWiFiCredentials] {
        lock.withLock { accepted }
    }

    func provisioningKey() async throws -> WiFiProvisioningKey {
        lock.withLock {
            let key = WiFiProvisioningKey(
                kid: "key-\(issued.count)",
                pk: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
            )
            issued.append(key)
            return key
        }
    }

    func scanNetworks() async throws -> [String] {
        WiFiScanResult.networks(in: scanReply)
    }

    func connectSealed(_ payload: SealedWiFiCredentials) async throws {
        try lock.withLock {
            guard refusals >= refusesFirst else {
                refusals += 1
                throw BLECommandError.badCredentials
            }
            accepted.append(payload)
        }
    }

    func wifiStatus() async throws -> WiFiStatus {
        let reads = lock.withLock { () -> Int in
            statusReads += 1
            return statusReads
        }
        return reads >= connectsAfterReads
            ? WiFiStatus(mode: .wlan, connected: "Home")
            : WiFiStatus(mode: .hotspot, connected: nil)
    }
}
