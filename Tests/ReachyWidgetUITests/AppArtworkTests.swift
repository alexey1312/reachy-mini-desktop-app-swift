import Foundation
import ReachyKit
@testable import ReachyWidgetUI
import Testing

/// A Space has no thumbnail — an emoji on a two-colour gradient is the whole
/// visual identity the Hub gives it, and both halves arrive as palette *names*.
@Suite("App artwork")
struct AppArtworkTests {
    private func app(_ extra: String) throws -> RobotApp {
        try JSONDecoder().decode(RobotApp.self, from: Data(#"""
        {"name": "x", "source_kind": "hf_space", "extra": \#(extra)}
        """#.utf8))
    }

    @Test("the Hub's palette names resolve to colours")
    func resolvesKnownPalette() throws {
        let app = try app(#"{"cardData": {"colorFrom": "pink", "colorTo": "indigo"}}"#)

        #expect(AppArtwork(app: app).colors.count == 2)
        #expect(AppArtwork.color(named: "pink") != AppArtwork.color(named: "indigo"))
    }

    /// The Hub adds palette names without asking. An unknown one has to render as
    /// *something* — a card with no artwork reads as a broken app.
    @Test("an unknown palette name still renders")
    func fallsBackForUnknownPalette() throws {
        let app = try app(#"{"cardData": {"colorFrom": "chartreuse", "colorTo": "octarine"}}"#)

        #expect(AppArtwork(app: app).colors.count == 2)
    }

    @Test("an app with no card at all still gets a gradient")
    func fallsBackWithNoCard() throws {
        let artwork = try AppArtwork(app: app("{}"))

        #expect(artwork.colors.count == 2)
        #expect(artwork.emoji == nil)
    }

    /// Two apps with no palette must not all come out the same colour, or the
    /// installed list turns into a wall of identical grey tiles.
    @Test("apps with no palette are still told apart by colour")
    func derivesAStableColourFromTheName() throws {
        func installed(_ name: String) throws -> AppArtwork {
            try AppArtwork(app: JSONDecoder().decode(RobotApp.self, from: Data(#"""
            {"name": "\#(name)", "source_kind": "installed", "extra": {}}
            """#.utf8)))
        }

        let dance = try installed("dance_party")
        let chess = try installed("chess")
        // Stable across launches: the same app must not change colour on a reload,
        // which rules out `hashValue` (seeded per process).
        let danceAgain = try installed("dance_party")

        #expect(dance.colors != chess.colors)
        #expect(dance.colors == danceAgain.colors)
    }
}
