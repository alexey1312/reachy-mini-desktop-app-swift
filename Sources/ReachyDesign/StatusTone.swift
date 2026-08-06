import SwiftUI

/// How a thing is doing, in the three states every status line in this app
/// actually distinguishes.
///
/// A caller maps its own domain type onto this — a process state, a reachability
/// check, a widget tile — which is what keeps this module free of any dependency
/// on `ReachyKit`.
public enum StatusTone: Sendable, CaseIterable {
    /// Up and doing what it should.
    case active
    /// Nothing wrong and nothing happening: idle, finished, not answering.
    case idle
    /// It stopped on an error.
    case failed
}

public extension StatusTone {
    var tone: Tone {
        switch self {
        case .active: .success
        case .idle: .quiet
        case .failed: .danger
        }
    }

    var style: AnyShapeStyle {
        tone.style
    }
}

/// One state caption, in the shape three surfaces render it with today.
///
/// `lineLimit` has no default limit on purpose: each of those three already
/// bounds it differently — two lines on the dock, one on a widget tile, none in
/// the robot list — so adopting this type has to preserve each, not average them.
public struct ReachyStatusLabel: View {
    private let text: String
    private let tone: StatusTone
    private let font: Font
    private let lineLimit: Int?

    public init(text: String, tone: StatusTone, font: Font = Typography.status, lineLimit: Int? = nil) {
        self.text = text
        self.tone = tone
        self.font = font
        self.lineLimit = lineLimit
    }

    public var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(tone.style)
            .lineLimit(lineLimit)
    }
}
