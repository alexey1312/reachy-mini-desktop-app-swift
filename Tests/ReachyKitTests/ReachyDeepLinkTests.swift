import Foundation
@testable import ReachyKit
import Testing

/// The scheme is shared with the OAuth callback, so parsing has to be exact:
/// anything it does not recognise belongs to somebody else.
@Suite("Deep links")
struct ReachyDeepLinkTests {
    @Test("a link round-trips through its URL")
    func roundTrips() {
        for link in ReachyDeepLink.allCases {
            #expect(ReachyDeepLink(url: link.url) == link)
        }
    }

    @Test("the robot link names the app's own scheme")
    func usesTheAppScheme() {
        #expect(ReachyDeepLink.robot.url.scheme == "reachy-mini-swift")
    }

    /// The destination is a URL *host*, which is case-insensitive and normalised as
    /// such — so a raw value carrying case would not survive the round trip above.
    @Test("no destination depends on its case surviving a URL")
    func namesDestinationsInLowercase() {
        for link in ReachyDeepLink.allCases {
            #expect(link.rawValue == link.rawValue.lowercased())
        }
    }

    @Test("the running app has a destination of its own")
    func addressesTheRunningApp() throws {
        let url = try #require(URL(string: "reachy-mini-swift://running-app"))

        #expect(ReachyDeepLink(url: url) == .runningApp)
    }

    /// `ASWebAuthenticationSession` claims the callback while a sign-in is running,
    /// but the app must not mistake one for a destination if it ever arrives here.
    @Test("the OAuth callback is not a destination")
    func ignoresTheOAuthCallback() throws {
        let callback = try #require(URL(string: "reachy-mini-swift://oauth-callback?code=abc"))

        #expect(ReachyDeepLink(url: callback) == nil)
    }

    @Test("another app's scheme is not ours")
    func ignoresAForeignScheme() throws {
        let foreign = try #require(URL(string: "reachy-mini://robot"))

        #expect(ReachyDeepLink(url: foreign) == nil)
    }

    @Test("an unknown destination in our own scheme is refused rather than guessed")
    func refusesAnUnknownDestination() throws {
        let unknown = try #require(URL(string: "reachy-mini-swift://telemetry"))

        #expect(ReachyDeepLink(url: unknown) == nil)
    }
}
