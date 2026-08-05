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
