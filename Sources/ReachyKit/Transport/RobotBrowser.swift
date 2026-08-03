import Foundation
import Network
import Observation

/// Bonjour discovery of robot daemons.
///
/// Watches both service types the daemon advertises: `_reachy-mini._tcp`
/// (primary) and `_http._tcp` (legacy, instance names containing "reachy").
/// A browser stuck in `.waiting(kDNSServiceErr_PolicyDenied)` means the user
/// denied Local Network permission — discovery is otherwise silently empty.
@MainActor
@Observable
public final class RobotBrowser {
    public struct DiscoveredService: Identifiable, Hashable, Sendable {
        public var id: String {
            "\(type)/\(name)"
        }

        public let name: String
        public let type: String
        public let endpoint: NWEndpoint
    }

    public private(set) var servicesByType: [String: [DiscoveredService]] = [:]
    public private(set) var browserStates: [String: String] = [:]
    private var browsers: [NWBrowser] = []

    public nonisolated static let serviceTypes = ["_reachy-mini._tcp", "_http._tcp"]

    public init() {}

    public var services: [DiscoveredService] {
        servicesByType.values.flatMap(\.self).sorted { $0.id < $1.id }
    }

    public var permissionLooksDenied: Bool {
        browserStates.values.contains(where: Self.stateLooksPolicyDenied)
    }

    nonisolated static func stateLooksPolicyDenied(_ state: String) -> Bool {
        state.contains("PolicyDenied") || state.contains("-65570")
    }

    nonisolated static func acceptsService(name: String, type: String) -> Bool {
        !type.hasPrefix("_http") || name.localizedCaseInsensitiveContains("reachy")
    }

    public func start() {
        stop()
        for type in Self.serviceTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.browserStates[type] = "\(state)"
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap { result -> DiscoveredService? in
                    guard case let .service(name, serviceType, _, _) = result.endpoint,
                          Self.acceptsService(name: name, type: serviceType)
                    else { return nil }
                    return DiscoveredService(name: name, type: serviceType, endpoint: result.endpoint)
                }
                Task { @MainActor in
                    self?.servicesByType[type] = found
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    public func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
        servicesByType = [:]
        browserStates = [:]
    }
}

public enum BonjourResolver {
    /// Resolves a discovered Bonjour service to a concrete host:port by opening
    /// a throwaway TCP connection and reading the remote endpoint.
    public static func resolve(_ endpoint: NWEndpoint, timeout: Duration = .seconds(5)) async -> RobotAddress? {
        let connection = NWConnection(to: endpoint, using: .tcp)
        defer { connection.cancel() }
        return await withTaskGroup(of: RobotAddress?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let resumed = Atomic(false)
                    connection.stateUpdateHandler = { state in
                        let finish: (RobotAddress?) -> Void = { address in
                            guard !resumed.swap(true) else { return }
                            continuation.resume(returning: address)
                        }
                        switch state {
                        case .ready:
                            if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint,
                               let host = Self.hostString(host)
                            {
                                finish(RobotAddress(host: host, port: Int(port.rawValue)))
                            } else {
                                finish(nil)
                            }
                        case .failed, .cancelled:
                            finish(nil)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func hostString(_ host: NWEndpoint.Host) -> String? {
        switch host {
        case let .ipv4(address):
            // NWEndpoint appends an interface zone ("%lo0") that is garbage in a URL.
            return stripZone("\(address)")
        case let .ipv6(address):
            let value = "\(address)"
            // A link-local address cannot be routed without its interface zone.
            guard !value.lowercased().hasPrefix("fe80:") || value.contains("%") else { return nil }
            return value.lowercased().hasPrefix("fe80:") ? value : stripZone(value)
        case let .name(name, _):
            return name
        @unknown default:
            return nil
        }
    }

    private static func stripZone(_ s: String) -> String {
        s.split(separator: "%").first.map(String.init) ?? s
    }
}

/// Tiny lock-protected flag for one-shot continuation resumption.
private final class Atomic: @unchecked Sendable {
    private var value: Bool
    private let lock = NSLock()

    init(_ value: Bool) {
        self.value = value
    }

    func swap(_ newValue: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
