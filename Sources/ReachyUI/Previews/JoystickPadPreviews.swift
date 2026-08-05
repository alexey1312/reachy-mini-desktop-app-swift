@testable import ReachyUI
import SwiftUI

// A preview with no `traits:` is captured at full device size — Prefire defaults the trait list
// to `.device`. Components that should be measured at their intrinsic height opt out with
// `.sizeThatFitsLayout`.

#Preview("Joystick — screen") {
    JoystickPad { _ in }
        .padding()
}

#Preview("Joystick — component", traits: .sizeThatFitsLayout) {
    JoystickPad { _ in }
        .padding()
}

// The lit arc has no gesture behind it in a snapshot, so the deflection is injected.
#Preview("Joystick — turning", traits: .sizeThatFitsLayout) {
    JoystickPad(deflection: .init(x: 0.95, y: -0.2)) { _ in }
        .padding()
}
