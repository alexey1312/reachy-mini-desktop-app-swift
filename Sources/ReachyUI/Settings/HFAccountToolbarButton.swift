import HuggingFaceAuth
import SwiftUI

/// The Hugging Face account, in the leading slot of the navigation bar.
///
/// It lived in Settings, which is a robot's screen — and the account is not a
/// robot's. It outlives every connection, and it is needed *before* one: signing
/// in is what makes the list of remote robots exist at all, so burying it behind
/// a robot that has not been reached yet put it exactly where it could not be
/// found.
struct HFAccountToolbarButton: View {
    let action: () -> Void

    /// Optional for the same reason `SettingsScreen` reads it that way: the
    /// non-optional form traps where nothing was injected, and a host without a
    /// Hugging Face session should simply not show the control.
    @Environment(HFAccount.self) private var account: HFAccount?

    var body: some View {
        if let account {
            Button(action: action) {
                label(for: account.state)
            }
            .accessibilityLabel(accessibilityLabel(for: account.state))
        }
    }

    @ViewBuilder
    private func label(for state: HFAccount.State) -> some View {
        switch state {
        case .signedOut, .failed:
            Label("Account", systemImage: "person.crop.circle")
        case .signingIn:
            ProgressView().controlSize(.small)
        case let .signedIn(username):
            HFAvatar(username: username, size: 26)
        case let .needsReauth(username):
            // The session lapsed and cannot be renewed silently, which is worth
            // seeing before the next thing that needs it fails.
            HFAvatar(username: username ?? "?", size: 26)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .background(.background, in: .circle)
                }
        }
    }

    private func accessibilityLabel(for state: HFAccount.State) -> String {
        switch state {
        case .signedOut, .failed: "Sign in to Hugging Face"
        case .signingIn: "Signing in to Hugging Face"
        case let .signedIn(username): "Hugging Face account: \(username)"
        case .needsReauth: "Hugging Face session expired"
        }
    }
}

extension View {
    /// Puts the account button in the leading slot of whatever navigation bar this
    /// view has.
    ///
    /// The placement is spelled out per platform because `.topBarLeading` is
    /// `@available(macOS, unavailable)`; `.navigation` is its counterpart there.
    /// Every other toolbar in this package leaves the placement to `.automatic`,
    /// which resolves trailing — that is where Settings already sits, and this has
    /// to be the other side of it.
    func hfAccountToolbar(isPresented: Binding<Bool>) -> some View {
        toolbar {
            #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    HFAccountToolbarButton { isPresented.wrappedValue = true }
                }
            #else
                ToolbarItem(placement: .topBarLeading) {
                    HFAccountToolbarButton { isPresented.wrappedValue = true }
                }
            #endif
        }
    }
}
