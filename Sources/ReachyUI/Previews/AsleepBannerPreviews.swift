import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Asleep banner — motors off", traits: .sizeThatFitsLayout) {
    AsleepBanner(session: .preview(status: .preview(motorMode: .disabled)))
        .padding()
}

#Preview("Asleep banner — backend stopped", traits: .sizeThatFitsLayout) {
    AsleepBanner(session: .preview(status: .preview(state: .stopped)))
        .padding()
}

#Preview("Asleep banner — waking up", traits: .sizeThatFitsLayout) {
    AsleepBanner(session: .preview(status: .preview(motorMode: .disabled), powerTransition: .wakingUp))
        .padding()
}
