import Foundation
import Network
import Observation

/// Phase 0.4 spike: Bonjour discovery of the robot daemon.
///
/// Watches both service types the daemon advertises: `_reachy-mini._tcp`
/// (primary) and `_http._tcp` (legacy, instance names containing "reachy").
/// A browser stuck in `.waiting(kDNSServiceErr_PolicyDenied)` means the user
/// denied Local Network permission — discovery is otherwise silently empty.
@MainActor
@Observable
final class DiscoveryModel {
    struct Service: Identifiable, Hashable {
        var id: String {
            "\(type)/\(name)"
        }

        let name: String
        let type: String
    }

    private(set) var servicesByType: [String: [Service]] = [:]
    private(set) var browserStates: [String: String] = [:]
    private var browsers: [NWBrowser] = []

    var services: [Service] {
        servicesByType.values.flatMap(\.self).sorted { $0.id < $1.id }
    }

    var permissionLooksDenied: Bool {
        browserStates.values.contains { $0.contains("PolicyDenied") || $0.contains("-65570") }
    }

    func start() {
        stop()
        for type in ["_reachy-mini._tcp", "_http._tcp"] {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.browserStates[type] = "\(state)"
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap { result -> Service? in
                    guard case let .service(name, serviceType, _, _) = result.endpoint else { return nil }
                    // Legacy _http._tcp: only instances that look like a Reachy
                    if serviceType.hasPrefix("_http"), !name.lowercased().contains("reachy") {
                        return nil
                    }
                    return Service(name: name, type: serviceType)
                }
                Task { @MainActor in
                    self?.servicesByType[type] = found
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
        servicesByType = [:]
        browserStates = [:]
    }
}
