import Foundation
import ReachyDesign
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

    /// Changes whenever the Hugging Face session changes, so a presented screen
    /// restarts the load that belongs to the new account.
    private(set) var accountGeneration = 0

    private let listing: any CentralRobotListing
    private let isSignedIn: @MainActor () -> Bool
    private var attemptedLoad = false
    /// Which request is allowed to write back, and whether one is running.
    ///
    /// Two are easy to have in flight at once — the screen's `.task` and a
    /// pull-to-refresh land on the same model — and central answers them in
    /// whatever order it likes. Without this the *older* answer wins simply by
    /// arriving second, which is how a list of robots turns into "none online" a
    /// moment after it appeared. Same rule as `RobotSession.connectionAttemptID`: a
    /// superseded request never writes back. An account change bumps it too, so an
    /// answer that lands afterwards cannot repopulate a list the account no longer
    /// owns.
    ///
    /// Named for the newest rather than shadowed by a local of the same name inside
    /// `fetch`: `self.` would be load-bearing there, and swiftformat's
    /// `redundantSelf` is exactly the kind of rule that decides otherwise.
    private var latestAttempt = 0
    private var isFetching = false

    public init(listing: any CentralRobotListing, isSignedIn: @escaping @MainActor () -> Bool) {
        self.listing = listing
        self.isSignedIn = isSignedIn
    }

    /// Drops account-scoped data before another Hugging Face session can see it.
    /// Incrementing the generation also restarts a presented screen's load.
    func accountChanged() {
        latestAttempt += 1
        isFetching = false
        state = .signedOut
        lastRefreshError = nil
        attemptedLoad = false
        accountGeneration += 1
    }

    /// A signed-in account has pending content before `.task` gets its first turn,
    /// even though `state` has not entered `.loading` yet — which is the first frame
    /// the sheet draws, and it must not be an empty-state.
    var isContentLoading: Bool {
        isSignedIn() && !state.hasRobots && (state == .loading || !attemptedLoad)
    }

    /// The screen's own load, on presentation. A second one while the first is
    /// still in flight would spend a round trip asking central the same question.
    public func load() async {
        guard !isFetching else { return }
        await fetch(showingSpinner: !state.hasRobots)
    }

    /// Pull to refresh. Always asks — the user asked — and supersedes whatever was
    /// in flight rather than queueing behind it.
    public func refresh() async {
        await fetch(showingSpinner: !state.hasRobots)
    }

    private func fetch(showingSpinner: Bool) async {
        guard isSignedIn() else {
            latestAttempt += 1
            isFetching = false
            state = .signedOut
            lastRefreshError = nil
            attemptedLoad = false
            return
        }
        attemptedLoad = true
        if showingSpinner {
            state = .loading
        }
        latestAttempt += 1
        let attempt = latestAttempt
        isFetching = true
        defer {
            if attempt == latestAttempt {
                isFetching = false
            }
        }
        do {
            let robots = try await listing.robots()
            guard attempt == latestAttempt else { return }
            state = robots.isEmpty ? .empty : .listed(robots)
            lastRefreshError = nil
        } catch {
            guard attempt == latestAttempt else { return }
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
            String(localized: .reachy("Sign in to Hugging Face to see your robots."))
        case .unauthorized:
            String(localized: .reachy("Hugging Face refused this session."))
        case .rateLimited:
            // Central allows 1200 requests a minute per token, and retrying at
            // once turns a limit into a ban.
            String(localized: .reachy("Too many requests. Wait a moment before refreshing again."))
        case let .http(code):
            String(localized: .reachy("Hugging Face answered \(code)."))
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
        /// A model parked in the given state. `YourReachiesScreen` suppresses its
        /// initial load in preview mode so the first frame is already final.
        ///
        /// `refreshFailure` is the one combination `load()` cannot reach on its
        /// own: a list already on screen, and a refresh that failed over it.
        static func preview(_ state: State = .signedOut, refreshFailure: String? = nil) -> YourReachiesModel {
            let model = YourReachiesModel(
                listing: PreviewListing(state: state, refreshFailure: refreshFailure),
                isSignedIn: { state != .signedOut }
            )
            model.state = state
            model.attemptedLoad = state != .loading && state != .signedOut
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
                // Kept complete for callers outside `YourReachiesScreen`; previews of
                // that screen suppress the request before it reaches this fixture.
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
