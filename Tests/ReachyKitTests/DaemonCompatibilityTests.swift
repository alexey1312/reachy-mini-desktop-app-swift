@testable import ReachyKit
import Testing

@Suite("DaemonCompatibilityPolicy")
struct DaemonCompatibilityTests {
    @Test("tested baseline is supported")
    func baseline() {
        #expect(DaemonCompatibilityPolicy.evaluate("1.9.0") == .supported)
        #expect(DaemonCompatibilityPolicy.evaluate("v1.9.0") == .supported)
    }

    @Test("older and different-major daemons are blocked", arguments: ["1.8.9", "2.0.0", "0.99.0"])
    func unsupported(version: String) {
        #expect(DaemonCompatibilityPolicy.evaluate(version) == .unsupported(
            reported: version,
            minimum: DaemonCompatibilityPolicy.minimumVersion
        ))
    }

    @Test("newer compatible versions connect with a warning", arguments: ["1.9.1", "1.10.0"])
    func newer(version: String) {
        #expect(DaemonCompatibilityPolicy.evaluate(version) == .untestedNewer(
            reported: version,
            tested: DaemonCompatibilityPolicy.testedVersion
        ))
    }

    @Test("missing or malformed versions degrade to unknown", arguments: [nil, "", "dev", "1.9"] as [String?])
    func unknown(version: String?) {
        #expect(DaemonCompatibilityPolicy.evaluate(version) == .unknown(reported: version))
    }
}
