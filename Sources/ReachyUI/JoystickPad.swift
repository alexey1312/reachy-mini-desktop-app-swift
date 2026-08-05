import SwiftUI

/// Which rotation zone the knob is in.
enum JoystickRotationSide: Equatable {
    case left, right
}

/// 2D touch pad emitting a normalized deflection; snaps back to center on release.
///
/// Past `mapping.rotationThreshold` sideways the knob enters a rotation zone, which
/// the pad marks with a lit arc and a haptic tick. The pad only reports where the
/// knob is — turning that into head pose or body rotation is `TeleopDriver`'s job.
struct JoystickPad: View {
    var mapping: JoystickMapping
    var onChange: (JoystickDeflection) -> Void

    @State private var deflection: JoystickDeflection

    init(
        mapping: JoystickMapping = JoystickMapping(),
        deflection: JoystickDeflection = .zero,
        onChange: @escaping (JoystickDeflection) -> Void
    ) {
        self.mapping = mapping
        self.onChange = onChange
        _deflection = State(initialValue: deflection)
    }

    private var rotationSide: JoystickRotationSide? {
        guard abs(deflection.x) > mapping.rotationThreshold else { return nil }
        return deflection.x > 0 ? .right : .left
    }

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.3))
                Circle()
                    .strokeBorder(.tertiary, lineWidth: 1)
                zoneArc(.left)
                zoneArc(.right)
                Circle()
                    .fill(.tint)
                    .frame(width: 56, height: 56)
                    .offset(x: CGFloat(deflection.x) * radius, y: CGFloat(deflection.y) * radius)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(drag(radius: radius))
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact, trigger: rotationSide)
    }

    private func drag(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                deflection = JoystickDeflection(
                    x: Double(value.translation.width / radius).clamped(to: -1 ... 1),
                    y: Double(value.translation.height / radius).clamped(to: -1 ... 1)
                )
                onChange(deflection)
            }
            .onEnded { _ in
                withAnimation(.snappy) { deflection = .zero }
                onChange(.zero)
            }
    }

    /// Where the body starts turning. Lit while the knob is inside it.
    private func zoneArc(_ side: JoystickRotationSide) -> some View {
        Circle()
            .trim(from: 0, to: 0.1)
            .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(side == .right ? -18 : 162))
            .foregroundStyle(rotationSide == side ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .padding(3)
    }
}
