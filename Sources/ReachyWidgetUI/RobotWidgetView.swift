import SwiftUI

/// The widget's face.
///
/// Deliberately free of `WidgetKit`: the container background and the timeline
/// belong to the extension, and keeping them out of here is what lets this render
/// in a preview — and therefore in the snapshot suite — like any other view.
public struct RobotWidgetView: View {
    private let content: RobotWidgetContent

    public init(content: RobotWidgetContent) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: content.symbolName)
                .font(.title2)
                .foregroundStyle(content.isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            Spacer(minLength: 0)
            Text(content.title)
                .font(.headline)
                .lineLimit(1)
            Text(content.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Two lines because a relative date in a wordier language runs
                // past one at the small size, and a truncated "last seen" is the
                // one part of a stale reading that has to survive.
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
