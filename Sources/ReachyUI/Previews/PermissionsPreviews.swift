import ReachyKit
@testable import ReachyUI
import SwiftUI

// Nothing to do and nothing coloured — the state most readers open this on, and the
// one that has to look calm rather than like a checklist.
#Preview("Privacy — all allowed") {
    PreviewScene.permissions()
}

// The first run: three rows, three ways to ask. Bluetooth and the microphone say "not
// asked yet"; the local network says "not known yet", because its probe cannot tell
// the two apart.
#Preview("Privacy — nothing asked yet") {
    PreviewScene.permissions(bluetooth: .undetermined, localNetwork: .undetermined, microphone: .undetermined)
}

// The refusal that used to be invisible: unmuting did nothing at all and said nothing.
#Preview("Privacy — microphone denied") {
    PreviewScene.permissions(microphone: .denied)
}

// Discovery returns an empty list and every typed address fails, with no error from
// any of it — which is why this row exists at all.
#Preview("Privacy — local network denied") {
    PreviewScene.permissions(localNetwork: .denied)
}

// Screen Time or an MDM profile. Deliberately not worded as a refusal: the Settings
// toggle is there and this user cannot move it.
#Preview("Privacy — microphone restricted") {
    PreviewScene.permissions(microphone: .restricted)
}

// Allowed and unusable at once — the pair `CBManagerAuthorization` cannot express, so
// the second line only appears once something has built a central and asked the radio.
#Preview("Privacy — Bluetooth allowed but switched off") {
    PreviewScene.permissions(availability: .poweredOff)
}

// Every row blocked, which is also the widest the captions ever get.
#Preview("Privacy — everything refused") {
    PreviewScene.permissions(bluetooth: .denied, localNetwork: .denied, microphone: .denied)
}
