import Foundation
@testable import ReachyKit
import Testing

@Suite("BLE command wire format")
struct BLECommandTests {
    @Test("arguments keep their case and spacing, even though the verb is matched uppercased")
    func preservesArgumentCasing() {
        #expect(BLECommand.wifiForget(ssid: "MyНome WiFi").wireFormat == "WIFI_FORGET MyНome WiFi")
        #expect(BLECommand.authenticate(pin: "4A7f9").wireFormat == "PIN_4A7f9")
        #expect(BLECommand.runScript("HOTSPOT").wireFormat == "CMD_HOTSPOT")
    }

    @Test("the sealed payload rides as one JSON blob after the verb")
    func formatsTheSealedPayload() {
        let json = #"{"ssid":"net","kid":"k","epk":"e","nonce":"n","ct":"c"}"#

        #expect(BLECommand.wifiConnectSealed(json: json).wireFormat == "WIFI_CONNECT_ENC \(json)")
    }

    @Test("only CMD_* is unanswerable — its handler returns nothing and the robot crashes encoding it")
    func marksScriptsAsFireAndForget() {
        #expect(BLECommand.runScript("RESTART_DAEMON").repliesToWrite == false)
        #expect(BLECommand.ping.repliesToWrite)
        #expect(BLECommand.wifiScan.repliesToWrite)
    }

    @Test("the key exchange is public — a bare public key is useless without the PIN")
    func classifiesPrivilegedCommands() {
        #expect(BLECommand.wifiKeyExchange.needsSession == false)
        #expect(BLECommand.wifiStatus.needsSession == false)
        #expect(BLECommand.ping.needsSession == false)
        #expect(BLECommand.wifiScan.needsSession)
        #expect(BLECommand.wifiForget(ssid: "x").needsSession)
        #expect(BLECommand.updateStart.needsSession)
    }

    @Test("a scan gets far longer than a ping — nmcli rescan alone runs about 15 s")
    func budgetsProxiedCommandsGenerously() {
        #expect(BLECommand.wifiScan.timeout > BLECommand.ping.timeout)
        #expect(BLECommand.updateStart.timeout >= .seconds(30))
    }
}

@Suite("BLE response parsing")
struct BLEResponseParserTests {
    @Test("every documented error string maps to a case the UI can act on")
    func parsesDocumentedErrors() {
        let cases: [(String, BLECommandError)] = [
            ("ERROR: Not connected. Please authenticate first.", .notAuthenticated),
            ("ERROR: Incorrect PIN", .incorrectPIN),
            ("ERROR: Bad credentials (wrong PIN?)", .badCredentials),
            ("ERROR: Busy", .busy),
            ("ERROR: Unknown ssid", .unknownSSID),
            ("ERROR: Cannot forget hotspot", .cannotForgetHotspot),
            ("ERROR: Daemon unreachable", .daemonUnreachable),
            ("ERROR: Invalid payload (expected JSON)", .invalidPayload),
            ("ERROR: Missing field ssid", .invalidPayload),
        ]
        for (raw, expected) in cases {
            #expect(BLEResponseParser.parse(raw) == .failure(expected), "\(raw)")
        }
    }

    @Test("the lockout carries its remaining seconds — the only number worth showing")
    func parsesTheLockoutCountdown() {
        #expect(BLEResponseParser.parse("ERROR: Too many attempts. Try again in 40s.")
            == .failure(.lockedOut(seconds: 40)))
        #expect(BLEResponseParser.parse("ERROR: Too many attempts. Try again in 5s.")
            == .failure(.lockedOut(seconds: 5)))
    }

    @Test("an error this app has never seen keeps its text rather than being swallowed")
    func keepsUnknownErrorText() {
        #expect(BLEResponseParser.parse("ERROR: Something new") == .failure(.other("Something new")))
    }

    @Test("the ack a proxied command answers with is recognisable, and is not a result")
    func recognisesTheWorkingAck() {
        #expect(BLEResponseParser.parse("OK: working").isWorkingAck)
        #expect(BLEResponseParser.parse("OK: Connected").isWorkingAck == false)
        #expect(BLEResponseParser.parse(BLEReply.workingAck).isWorkingAck)
    }

    @Test("a payload keeps its newlines — the journal's last line depends on the final one")
    func keepsPayloadWhitespaceVerbatim() {
        // Trimming this is what made `BLEJournalReader` hold the last line of every chunk
        // back and glue it onto the next one, corrupting a line per read boundary.
        #expect(BLEResponseParser.parse("one\ntwo\n") == .payload("one\ntwo\n"))
        #expect(BLEResponseParser.parse("partial") == .payload("partial"))
        // Recognised messages still trim: their trailing whitespace carries nothing.
        #expect(BLEResponseParser.parse("OK: Connected\n") == .ok("Connected"))
        #expect(BLEResponseParser.parse(" PONG \n") == .pong)
    }

    @Test("plain replies, echoes and JSON payloads are told apart")
    func parsesNonErrorReplies() {
        #expect(BLEResponseParser.parse("PONG") == .pong)
        #expect(BLEResponseParser.parse("OK: Named kitchen-reachy") == .ok("Named kitchen-reachy"))
        #expect(BLEResponseParser.parse("ECHO: WIFI_SCANN") == .echo("WIFI_SCANN"))
        #expect(BLEResponseParser.parse(#"["Net A","Net B"]"#) == .payload(#"["Net A","Net B"]"#))
    }
}

@Suite("BLE PIN session")
struct BLEPinSessionTests {
    private let start = ContinuousClock.now

    @Test("a disconnect drops the session but keeps the lockout — the robot penalty is global")
    func lockoutSurvivesDisconnect() {
        var session = BLEPinSession()
        session.lockedOut(for: 40, at: start)

        session.invalidate()

        #expect(session.isAuthenticated(at: start) == false)
        #expect(session.lockoutRemaining(at: start) != nil)
    }

    @Test("reconnecting always needs the PIN again, even inside the 300 s window")
    func sessionDoesNotSurviveDisconnect() {
        var session = BLEPinSession()
        session.authenticated(at: start)
        #expect(session.isAuthenticated(at: start))

        session.invalidate()

        #expect(session.isAuthenticated(at: start) == false)
    }

    @Test("the session expires after its 300 s time to live")
    func sessionExpires() {
        var session = BLEPinSession()
        session.authenticated(at: start)

        #expect(session.isAuthenticated(at: start.advanced(by: .seconds(299))))
        #expect(session.isAuthenticated(at: start.advanced(by: .seconds(301))) == false)
    }

    @Test("three attempts are free, and the count is shown before the lockout bites")
    func countsFreeAttempts() {
        var session = BLEPinSession()
        #expect(session.attemptsBeforeLockout == 3)

        session.failed(at: start)
        session.failed(at: start)

        #expect(session.attemptsBeforeLockout == 1)
    }

    @Test("a correct PIN clears the counter as well as opening the session")
    func successResetsTheThrottle() {
        var session = BLEPinSession()
        session.failed(at: start)
        session.failed(at: start)

        session.authenticated(at: start)

        #expect(session.attemptsBeforeLockout == 3)
        #expect(session.lockoutRemaining(at: start) == nil)
    }

    @Test("the lockout runs out on its own")
    func lockoutExpires() {
        var session = BLEPinSession()
        session.lockedOut(for: 30, at: start)

        #expect(session.lockoutRemaining(at: start.advanced(by: .seconds(29))) != nil)
        #expect(session.lockoutRemaining(at: start.advanced(by: .seconds(31))) == nil)
    }
}

@Suite("BLE network status parsing")
struct WiFiNetworkStatusTests {
    @Test("a joined robot reports its LAN address")
    func parsesConnected() throws {
        let status = try #require(WiFiNetworkStatus(parsing: "CONNECTED [wlan0] 192.168.1.42"))

        #expect(status.mode == .connected)
        #expect(status.address == "192.168.1.42")
    }

    @Test("hotspot mode reports the well-known gateway")
    func parsesHotspot() throws {
        let status = try #require(WiFiNetworkStatus(parsing: "HOTSPOT [wlan0] 10.42.0.1"))

        #expect(status.mode == .hotspot)
        #expect(status.address == "10.42.0.1")
    }

    @Test("several interfaces are split on the separator, and wlan0 wins")
    func parsesMultipleInterfaces() throws {
        let status = try #require(WiFiNetworkStatus(parsing: "CONNECTED [eth0] 10.0.0.5 ; [wlan0] 192.168.1.42"))

        #expect(status.interfaces.count == 2)
        #expect(status.address == "192.168.1.42")
    }

    @Test("with no interfaces at all the value is a bare mode, with no bracket section")
    func parsesBareOffline() throws {
        let status = try #require(WiFiNetworkStatus(parsing: "OFFLINE"))

        #expect(status.mode == .offline)
        #expect(status.interfaces.isEmpty)
        #expect(status.address == nil)
    }

    @Test("anything unparseable is nil rather than a wrong answer")
    func rejectsGarbage() {
        #expect(WiFiNetworkStatus(parsing: "") == nil)
        #expect(WiFiNetworkStatus(parsing: "banana [wlan0] 1.2.3.4") == nil)
    }
}

@Suite("WiFiStatus decoding")
struct WiFiStatusDecodingTests {
    private func decode(_ json: String) throws -> WiFiStatus {
        try JSONDecoder().decode(WiFiStatus.self, from: Data(json.utf8))
    }

    @Test("an authenticated reply carries the saved-network list")
    func decodesAuthenticatedReply() throws {
        let status = try decode(#"{"mode":"wlan","connected":"Home","known":["Home","Cafe"],"error":null}"#)

        #expect(status.mode == .wlan)
        #expect(status.known == ["Home", "Cafe"])
        #expect(status.hasJoined("Home"))
    }

    @Test("a daemon the BLE service cannot reach reports a null mode, not a failure")
    func decodesDaemonUnreachable() throws {
        let status = try decode(#"{"mode":null,"connected":null,"error":"daemon_unreachable"}"#)

        #expect(status.mode == nil)
        #expect(status.error == "daemon_unreachable")
    }

    @Test("the HTTP route spells the same two fields differently")
    func decodesTheHTTPSpelling() throws {
        let status = try decode(#"{"mode":"hotspot","connected_network":"Home","known_networks":["Home"]}"#)

        #expect(status.connected == "Home")
        #expect(status.known == ["Home"])
        #expect(status.didFallBackToHotspot)
    }

    @Test("a mode this app has never heard of does not break a status poll mid-provisioning")
    func toleratesAnUnknownMode() throws {
        let status = try decode(#"{"mode":"reticulating","connected":null,"tomorrows_field":1}"#)

        #expect(status.mode == nil)
        #expect(status.hasJoined("Home") == false)
    }
}
