import Network
@testable import ReachyKit
import Testing

@Suite("RobotBrowser")
struct RobotBrowserTests {
    @Test("watches the primary and legacy service types")
    func serviceTypes() {
        #expect(RobotBrowser.serviceTypes == ["_reachy-mini._tcp", "_http._tcp"])
    }

    @Test("legacy HTTP discovery filters unrelated services")
    func legacyFilter() {
        #expect(RobotBrowser.acceptsService(name: "Reachy Mini", type: "_http._tcp"))
        #expect(!RobotBrowser.acceptsService(name: "Printer", type: "_http._tcp"))
        #expect(RobotBrowser.acceptsService(name: "robot", type: "_reachy-mini._tcp"))
    }

    @Test("policy denial recognizes symbolic and numeric Network errors")
    func policyDenial() {
        #expect(RobotBrowser.stateLooksPolicyDenied("waiting(PolicyDenied)"))
        #expect(RobotBrowser.stateLooksPolicyDenied("DNS error -65570"))
        #expect(!RobotBrowser.stateLooksPolicyDenied("ready"))
    }

    @Test("global IPv6 is accepted but zone-less link-local IPv6 is dropped")
    func ipv6Candidates() throws {
        let global = try #require(IPv6Address("fd00::1234"))
        let linkLocal = try #require(IPv6Address("fe80::1234"))
        #expect(BonjourResolver.hostString(.ipv6(global)) == "fd00::1234")
        #expect(BonjourResolver.hostString(.ipv6(linkLocal)) == nil)
    }
}
