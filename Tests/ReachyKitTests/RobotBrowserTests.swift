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
        #expect(LocalNetworkProbe.looksPolicyDenied("waiting(PolicyDenied)"))
        #expect(LocalNetworkProbe.looksPolicyDenied("DNS error -65570"))
        #expect(!LocalNetworkProbe.looksPolicyDenied("ready"))
    }

    @Test("the hardware id comes off the TXT record the daemon publishes")
    func hardwareIDFromTXT() {
        let advert = NWBrowser.Result.Metadata.bonjour(NWTXTRecord([
            "version": "1.9.0",
            "unit_id": "b68ff6bbe47f0608",
            "robot_name": "reachy_mini",
        ]))
        #expect(RobotBrowser.hardwareID(from: advert) == "b68ff6bbe47f0608")
    }

    @Test("an advert without a unit id matches no stored robot")
    func hardwareIDMissing() {
        #expect(RobotBrowser.hardwareID(from: .bonjour(NWTXTRecord(["version": "1.9.0"]))) == nil)
        #expect(RobotBrowser.hardwareID(from: .none) == nil)
    }

    @Test("global IPv6 is accepted but zone-less link-local IPv6 is dropped")
    func ipv6Candidates() throws {
        let global = try #require(IPv6Address("fd00::1234"))
        let linkLocal = try #require(IPv6Address("fe80::1234"))
        #expect(BonjourResolver.hostString(.ipv6(global)) == "fd00::1234")
        #expect(BonjourResolver.hostString(.ipv6(linkLocal)) == nil)
    }
}
