import Foundation
@testable import ReachyKit
import Testing

/// `/wifi/*` mounts at the app root and only under `--wireless-version`, so the
/// simulator cannot serve any of it — `wifi_config.py` imports `nmcli` and
/// `cryptography` at module scope, and neither is in `.venv-sim`. Stubs and real
/// hardware are the whole of the coverage.
@Suite("Wi-Fi config over HTTP")
struct RobotConnectionWiFiTests {
    private func makeSession(_ stubs: [String: StubURLProtocol.Stub]) -> URLSession {
        StubURLProtocol.makeSession(stubs)
    }

    private func makeConnection(_ session: URLSession) throws -> RobotConnection {
        try RobotConnection(address: RobotAddress(host: "10.42.0.1"), session: session)
    }

    private static let sealed = SealedWiFiCredentials(
        ssid: "Home",
        kid: "key-0",
        epk: "ZXBr",
        nonce: "bm9uY2U=",
        ct: "Y2lwaGVy"
    )

    @Test("the provisioning key comes back with the algorithm it was sealed under")
    func readsTheProvisioningKey() async throws {
        let session = makeSession([
            "/wifi/prov_key": .init(
                statusCode: 200,
                json: #"{"kid":"k1","pk":"cGs=","alg":"x25519-hkdf-sha256-aesgcm"}"#
            ),
        ])

        let key = try await makeConnection(session).provisioningKey()

        #expect(key.kid == "k1")
        #expect(key.alg == WiFiProvisioningKey.supportedAlgorithm)
    }

    /// The scan is a POST because the route rescans the air before answering, and it is
    /// not capped the way the Bluetooth reply is — this list is the complete one.
    @Test("scanning is a POST and returns the full list")
    func scansOverHTTP() async throws {
        let session = makeSession(["/wifi/scan_and_list": .init(statusCode: 200, json: #"["Home","Cafe"]"#)])

        let networks = try await makeConnection(session).scanNetworks()

        #expect(networks == ["Home", "Cafe"])
        #expect(StubURLProtocol.requests(for: session).first?.httpMethod == "POST")
    }

    /// The whole reason `connect_sealed` exists. Upstream's plaintext `POST /wifi/connect`
    /// puts the PSK in a query string, and this client never calls it.
    @Test("the sealed payload never appears in the URL")
    func keepsTheSecretOutOfTheURL() async throws {
        let session = makeSession(["/wifi/connect_sealed": .init(statusCode: 200)])

        try await makeConnection(session).connectSealed(Self.sealed)

        let request = try #require(StubURLProtocol.requests(for: session).first)
        let url = try #require(request.url?.absoluteString)
        #expect(request.httpMethod == "POST")
        #expect(url == "http://10.42.0.1:8000/wifi/connect_sealed")
        #expect(!url.contains(Self.sealed.ct))
        #expect(!url.contains("password"))
    }

    /// The daemon answers `decrypt_failed` with a 400, which is a stale `kid` just as
    /// often as a wrong PIN. Mapping it onto the same case the Bluetooth path uses is
    /// what makes the one retry with a fresh key work over either channel.
    @Test("a refused payload maps onto the case that earns a retry")
    func mapsDecryptFailureToBadCredentials() async throws {
        let session = makeSession(["/wifi/connect_sealed": .init(statusCode: 400)])
        let connection = try makeConnection(session)

        await #expect(throws: BLECommandError.badCredentials) {
            try await connection.connectSealed(Self.sealed)
        }
    }

    @Test("another nmcli operation in flight reads as busy, not as a rejection")
    func mapsConflictToBusy() async throws {
        let session = makeSession(["/wifi/connect_sealed": .init(statusCode: 409)])
        let connection = try makeConnection(session)

        await #expect(throws: BLECommandError.busy) {
            try await connection.connectSealed(Self.sealed)
        }
    }

    @Test("status carries the saved networks the Bluetooth characteristic cannot")
    func readsStatus() async throws {
        let session = makeSession([
            "/wifi/status": .init(
                statusCode: 200,
                json: #"{"mode":"wlan","known_networks":["Home","Cafe"],"connected_network":"Home"}"#
            ),
        ])

        let status = try await makeConnection(session).wifiStatus()

        #expect(status.hasJoined("Home"))
        #expect(status.known == ["Home", "Cafe"])
    }

    /// A Lite robot has no `/wifi/*` at all, and that has to read as a missing feature
    /// rather than as a missing network.
    @Test("a robot without the wireless routes is reported as such")
    func reportsAbsentRoutes() async throws {
        let session = makeSession(["/wifi/status": .init(statusCode: 404)])
        let connection = try makeConnection(session)

        await #expect(throws: ReachyKitError.wirelessFeaturesUnavailable) {
            _ = try await connection.wifiStatus()
        }
    }

    /// `forget` is the one route where 404 is a real answer — the robot has no such
    /// saved network — so it must not be read as the route being absent.
    @Test("forgetting an unknown network is not mistaken for a missing route")
    func distinguishesAMissingNetworkFromAMissingRoute() async throws {
        let session = makeSession(["/wifi/forget": .init(statusCode: 404)])
        let connection = try makeConnection(session)

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 404)) {
            try await connection.forget(ssid: "Nowhere")
        }
    }

    @Test("the reason a join failed is read back from the robot")
    func readsTheLastError() async throws {
        let session = makeSession(["/wifi/error": .init(statusCode: 200, json: #"{"error":"Secrets were required"}"#)])

        #expect(try await makeConnection(session).lastWiFiError() == "Secrets were required")
    }

    @Test("no recorded error reads as no error, not as a failure")
    func readsNoError() async throws {
        let session = makeSession(["/wifi/error": .init(statusCode: 200, json: #"{"error":null}"#)])

        #expect(try await makeConnection(session).lastWiFiError() == nil)
    }
}
