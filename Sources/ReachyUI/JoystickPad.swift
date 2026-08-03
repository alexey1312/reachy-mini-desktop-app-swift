import SwiftUI

/// 2D touch pad emitting normalized (-1…1, -1…1); snaps back to center on release.
struct JoystickPad: View {
    var onChange: (_ x: Double, _ y: Double) -> Void

    @State private var knob: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.3))
                Circle()
                    .strokeBorder(.tertiary, lineWidth: 1)
                Circle()
                    .fill(.tint)
                    .frame(width: 56, height: 56)
                    .offset(knob)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clamped = CGSize(
                            width: value.translation.width.clamped(to: -radius ... radius),
                            height: value.translation.height.clamped(to: -radius ... radius)
                        )
                        knob = clamped
                        onChange(clamped.width / radius, clamped.height / radius)
                    }
                    .onEnded { _ in
                        withAnimation(.snappy) { knob = .zero }
                        onChange(0, 0)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
