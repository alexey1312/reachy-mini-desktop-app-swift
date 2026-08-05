import ReachyKit
import SwiftUI

/// What a Space looks like in a list.
///
/// The Hub gives an app no thumbnail at all — only `cardData.emoji` and two
/// palette *names* (`colorFrom` / `colorTo`) drawn from a fixed set. Resolving
/// those names is a UI concern, which is why `RobotApp.Gradient` carries them
/// unresolved.
struct AppArtwork {
    let emoji: String?
    let colors: [Color]

    init(app: RobotApp) {
        emoji = app.emoji
        if let gradient = app.gradient {
            colors = [Self.color(named: gradient.from), Self.color(named: gradient.to)]
        } else {
            // An installed app that lost its metadata has no palette. Deriving one
            // from the name keeps the list legible — and keeps it *stable*, which
            // a random colour would not.
            colors = Self.derivedColors(for: app.id)
        }
    }

    /// Tailwind's palette, which is what the Hub's card editor offers.
    static func color(named name: String) -> Color {
        switch name.lowercased() {
        case "red": .red
        case "orange": .orange
        case "amber", "yellow": .yellow
        case "lime", "green", "emerald", "teal": .green
        case "cyan", "sky", "blue": .blue
        case "indigo", "violet": .indigo
        case "purple", "fuchsia": .purple
        case "pink", "rose": .pink
        case "gray", "grey", "slate", "zinc", "neutral", "stone": .gray
        // The Hub adds names without asking; a card with no artwork reads as a
        // broken app, so an unfamiliar name still gets a colour.
        default: .accentColor
        }
    }

    private static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .indigo, .purple, .pink]

    private static func derivedColors(for key: String) -> [Color] {
        // A hash of our own rather than `hashValue`, which is seeded per process
        // and would repaint every app on each launch.
        var digest: UInt64 = 5381
        for byte in key.utf8 {
            digest = digest &* 33 &+ UInt64(byte)
        }
        let first = Int(digest % UInt64(palette.count))
        let second = Int((digest / UInt64(palette.count)) % UInt64(palette.count))
        return [palette[first], palette[second == first ? (second + 3) % palette.count : second]]
    }
}

/// The rounded tile a store row leads with.
struct AppArtworkTile: View {
    let app: RobotApp
    var size: CGFloat = 52

    var body: some View {
        let artwork = AppArtwork(app: app)
        RoundedRectangle(cornerRadius: size / 4.5, style: .continuous)
            .fill(
                LinearGradient(colors: artwork.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: size, height: size)
            .overlay {
                if let emoji = artwork.emoji {
                    Text(emoji)
                        .font(.system(size: size * 0.5))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .accessibilityHidden(true)
    }
}
