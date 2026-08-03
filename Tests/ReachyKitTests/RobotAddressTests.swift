import Foundation
@testable import ReachyKit
import Testing

@Suite("RobotAddress")
struct RobotAddressTests {
    @Test("root URL for a hostname")
    func rootURLHostname() {
        let address = RobotAddress(host: "reachy-mini.local")
        #expect(address.rootURL?.absoluteString == "http://reachy-mini.local:8000")
    }

    @Test("IPv6 literal is bracketed (upstream issue #269 regression)")
    func ipv6Bracketing() {
        let address = RobotAddress(host: "fd00::1234", port: 8000)
        #expect(address.rootURL?.absoluteString == "http://[fd00::1234]:8000")
        #expect(address.webSocketURL(path: "/api/state/ws/full")?.absoluteString
            == "ws://[fd00::1234]:8000/api/state/ws/full")
    }

    @Test("custom port is preserved")
    func customPort() {
        let address = RobotAddress(host: "10.0.0.5", port: 9000)
        #expect(address.rootURL?.absoluteString == "http://10.0.0.5:9000")
    }

    @Test(
        "parses user input with optional port (phone-testing regression: ip:port was bracketed as IPv6)",
        arguments: [
            ("192.168.50.75", "192.168.50.75", 8000),
            ("192.168.50.75:8000", "192.168.50.75", 8000),
            ("192.168.50.75:9001", "192.168.50.75", 9001),
            ("reachy-mini.local", "reachy-mini.local", 8000),
            ("reachy-mini.local:8000", "reachy-mini.local", 8000),
            ("fd00::1234", "fd00::1234", 8000),
            ("[fd00::1234]", "fd00::1234", 8000),
            ("[fd00::1234]:9001", "fd00::1234", 9001),
            (" 10.0.0.5 ", "10.0.0.5", 8000),
        ]
    )
    func parsing(input: String, host: String, port: Int) {
        let address = RobotAddress(parsing: input)
        #expect(address?.host == host)
        #expect(address?.port == port)
    }

    @Test("rejects garbage input", arguments: ["", "  ", "host:notaport", "[fd00::1234", "[fd00::1]x"])
    func parsingRejects(input: String) {
        #expect(RobotAddress(parsing: input) == nil)
    }
}
