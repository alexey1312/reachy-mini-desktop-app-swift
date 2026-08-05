import Foundation
import ReachyKit

/// Which of this account's robots central can see right now.
///
/// The list is the online signal — central sweeps a peer whose lease lapsed, so
/// a robot that is off is simply absent rather than listed as offline.
@MainActor
@Observable
public final class YourReachiesModel {
    /// `Sendable` explicitly: nested in a `@MainActor` type it would inherit that
    /// isolation, and the preview listing carries one across to a task.
    public enum State: Equatable, Sendable {
        /// No Hugging Face account, so there is nothing to ask central with.
        case signedOut
        case loading
        /// Central answered and this account owns nothing that is online.
        case empty
        case listed([CentralRobot])
        /// The token was refused. Retrying spends a round trip to be refused
        /// again; only a fresh sign-in changes anything.
        case needsSignIn
        case failed(String)
    }

    public private(set) var state: State = .signedOut
    /// Set when a refresh failed over a list that is still on screen. The robots
    /// did not go away — the request did — so the list stays and this explains
    /// why it did not change.
    public private(set) var lastRefreshError: String?

    private let listing: any CentralRobotListing
    private let isSignedIn: @MainActor () -> Bool

    public init(listing: any CentralRobotListing, isSignedIn: @escaping @MainActor () -> Bool) {
        self.listing = listing
        self.isSignedIn = isSignedIn
    }

    public func load() async {
        guard state != .loading else { return }
        await fetch(showingSpinner: !state.hasRobots)
    }

    public func refresh() async {
        await fetch(showingSpinner: !state.hasRobots)
    }

    private func fetch(showingSpinner: Bool) async {
        guard isSignedIn() else {
            state = .signedOut
            lastRefreshError = nil
            return
        }
        if showingSpinner {
            state = .loading
        }
        do {
            let robots = try await listing.robots()
            state = robots.isEmpty ? .empty : .listed(robots)
            lastRefreshError = nil
        } catch {
            report(error)
        }
    }

    /// A failure over an existing list annotates it; a failure over nothing
    /// replaces it, because there is nothing to preserve.
    private func report(_ error: any Error) {
        if case .unauthorized = error as? CentralRelayClient.Failure {
            state = .needsSignIn
            lastRefreshError = nil
            return
        }
        let reason = Self.describe(error)
        if state.hasRobots {
            lastRefreshError = reason
        } else {
            state = .failed(reason)
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let failure = error as? CentralRelayClient.Failure else {
            return error.localizedDescription
        }
        return switch failure {
        case .noToken:
            "Sign in to Hugging Face to see your robots."
        case .unauthorized:
            "Hugging Face refused this session."
        case .rateLimited:
            // Central allows 1200 requests a minute per token, and retrying at
            // once turns a limit into a ban.
            "Too many requests. Wait a moment before refreshing again."
        case let .http(code):
            "Hugging Face answered \(code)."
        }
    }
}

public extension YourReachiesModel.State {
    var hasRobots: Bool {
        if case .listed = self {
            true
        } else {
            false
        }
    }
}

#if DEBUG
    public extension YourReachiesModel {
        /// A model that *lands on* the given state rather than one parked in it.
        /// The screen calls `load()` when it appears, so a fixture that only set
        /// `state` would be overwritten the moment it was rendered — and a
        /// snapshot would catch whichever won.
        ///
        /// `refreshFailure` is the one combination `load()` cannot reach on its
        /// own: a list already on screen, and a refresh that failed over it.
        static func preview(_ state: State = .signedOut, refreshFailure: String? = nil) -> YourReachiesModel {
            let model = YourReachiesModel(
                listing: PreviewListing(state: state, refreshFailure: refreshFailure),
                isSignedIn: { state != .signedOut }
            )
            model.state = state
            return model
        }
    }

    private struct PreviewListing: CentralRobotListing {
        let state: YourReachiesModel.State
        let refreshFailure: String?

        func robots() async throws -> [CentralRobot] {
            if let refreshFailure {
                throw PreviewFailure(errorDescription: refreshFailure)
            }
            switch state {
            case let .listed(robots):
                return robots
            case .empty, .signedOut:
                return []
            case .needsSignIn:
                throw CentralRelayClient.Failure.unauthorized
            case let .failed(reason):
                throw PreviewFailure(errorDescription: reason)
            case .loading:
                // Never answers, which is exactly what being mid-request looks like.
                try await Task.sleep(for: .seconds(3600))
                return []
            }
        }
    }

    /// Carries a chosen message through `describe`, which falls back to
    /// `localizedDescription` for anything that is not a relay failure.
    private struct PreviewFailure: LocalizedError {
        let errorDescription: String?
    }
#endif
