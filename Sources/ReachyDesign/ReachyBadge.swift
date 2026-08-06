import SwiftUI

/// One word about the row it sits on, in a capsule.
///
/// It takes the `.badge` surface rather than a fill of its own — that role exists
/// for exactly this, a small marker on content that already carries a surface.
/// The tone colours the *text*, which is what removes the one pinned
/// `.foregroundStyle(.white)` this app had: white was legible only because the
/// capsule underneath was filled with `.tint`, and in a dark appearance a light
/// tint left white on light.
public struct ReachyBadge: View {
    private let text: String
    private let tone: Tone

    public init(_ text: String, tone: Tone = .brand) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(Typography.status.weight(.semibold))
            .foregroundStyle(tone.style)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .reachySurface(.badge, in: .capsule)
    }
}
