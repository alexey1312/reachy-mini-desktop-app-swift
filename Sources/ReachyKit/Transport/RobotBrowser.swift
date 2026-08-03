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

    public static let serviceTypes = ["_reachy-mini._tcp", "_http._tcp"]

    public init() {}

    public var services: [DiscoveredService] {
        servicesByType.values.flatMap(\.self).sorted { $0.id < $1.id }
    }

    public var permissionLooksDenied: Bool {
        browserStates.values.contains { $0.contains("PolicyDenied") || $0.contains("-65570") }
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
                    guard case let .service(name, serviceType, _, _) = result.endpoint else { return nil }
                    // Legacy _http._tcp: only instances that look like a Reachy
                    if serviceType.hasPrefix("_http"), !name.lowercased().contains("reachy") {
                        return nil
                    }
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
                            if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                                finish(RobotAddress(host: Self.hostString(host), port: Int(port.rawValue)))
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

    static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case let .ipv4(address):
            // NWEndpoint appends an interface zone ("%lo0") that is garbage in a URL
            stripZone("\(address)")
        case let .ipv6(address):
            // Zone is only meaningful (and required) for link-local addresses.
            // ponytail: fe80:: keeps its zone; URL layer must %-encode it — revisit
            // when a real link-local robot shows up
            "\(address)".hasPrefix("fe80") ? "\(address)" : stripZone("\(address)")
        case let .name(name, _):
            name
        @unknown default:
            "\(host)"
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
