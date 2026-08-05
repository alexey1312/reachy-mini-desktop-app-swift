import HuggingFaceAuth
import ReachyKit
import SwiftUI

/// The Hugging Face account this app holds, and whether this robot shares it.
///
/// Two custody points, and the card keeps them visibly apart: signing in here
/// gets the private half of the app store and the robot list; *linking* hands the
/// robot its own copy of the token, which is what puts it on the relay. Signing
/// out does not unlink — a robot left reachable with a token the user believes
/// they revoked is the one outcome worth going out of the way to prevent.
struct HFAccountSection: View {
    let session: RobotSession

    @State private var model: HFSignInModel
    @State private var robotAccount: HFAuthStatus?
    @State private var relay: RelayStatus?
    @State private var linkError: String?
    @State private var isLinking = false
    @State private var showsTokenField = false
    @Environment(\.reachyPreviewMode) private var previewMode

    init(
        session: RobotSession,
        model: HFSignInModel,
        robotAccount: HFAuthStatus? = nil,
        relay: RelayStatus? = nil,
        linkError: String? = nil
    ) {
        self.session = session
        _model = State(initialValue: model)
        _robotAccount = State(initialValue: robotAccount)
        _relay = State(initialValue: relay)
        _linkError = State(initialValue: linkError)
    }

    var body: some View {
        Section {
            accountRow
            if model.isBusy {
                ProgressView()
            }
            if let errorText = model.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            signInControls
        } header: {
            Text("Hugging Face")
        } footer: {
            Text(footerText)
        }

        if session.canLinkHuggingFace {
            robotSection
        }
    }

    // MARK: This app's account

    @ViewBuilder
    private var accountRow: some View {
        switch model.account.state {
        case .signedOut, .signingIn:
            Label("Not signed in", systemImage: "person.crop.circle")
        case let .signedIn(username):
            LabeledContent {
                Button("Sign out", role: .destructive) { model.signOut() }
                    .buttonStyle(.borderless)
            } label: {
                accountLabel(username: username, caption: "Signed in")
            }
        case let .needsReauth(username):
            accountLabel(username: username ?? "Your account", caption: "Session expired")
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func accountLabel(username: String, caption: String) -> some View {
        HStack(spacing: 10) {
            avatar(for: username)
            VStack(alignment: .leading, spacing: 1) {
                Text(username)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The Hub serves an avatar per username. A snapshot must not go to the
    /// network, so previews stop at the monogram the placeholder already draws.
    @ViewBuilder
    private func avatar(for username: String) -> some View {
        let monogram = Circle()
            .fill(.tint.opacity(0.2))
            .overlay { Text(username.prefix(1).uppercased()).font(.headline) }
            .frame(width: 32, height: 32)

        if previewMode {
            monogram
        } else if let url = URL(string: "https://huggingface.co/api/users/\(username)/avatar") {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                monogram
            }
            .frame(width: 32, height: 32)
            .clipShape(.circle)
        } else {
            monogram
        }
    }

    @ViewBuilder
    private var signInControls: some View {
        switch model.account.state {
        case .signedIn:
            EmptyView()
        default:
            if model.offersBrowserSignIn {
                Button {
                    Task { await model.signInWithBrowser() }
                } label: {
                    Label("Sign in with Hugging Face", systemImage: "person.badge.key")
                }
                .disabled(model.isBusy)
            }

            DisclosureGroup("Use an access token", isExpanded: $showsTokenField) {
                SecureField("hf_…", text: $model.pastedToken)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                Button("Sign in with this token") {
                    Task { await model.signInWithPastedToken() }
                }
                .disabled(model.pastedToken.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
            }
        }
    }

    private var footerText: String {
        if model.offersBrowserSignIn {
            "Signing in shows your private Spaces in the app store and lists your robots for remote access."
        } else {
            // Honest about the state of the build rather than showing a button
            // that would open an error page on the Hub.
            "One-tap sign-in is not available in this build. Create an access token at "
                + "huggingface.co/settings/tokens and paste it here."
        }
    }

    // MARK: This robot

    private var robotSection: some View {
        Section {
            LabeledContent("This robot", value: robotAccountText)
            if let relay {
                LabeledContent("Remote access", value: relayText(relay))
            }
            if let linkError {
                Text(linkError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if robotAccount?.isLoggedIn == true {
                Button("Unlink this robot", role: .destructive) {
                    Task { await unlink() }
                }
                .disabled(isLinking)
            } else if case .signedIn = model.account.state {
                Button {
                    Task { await link() }
                } label: {
                    if isLinking {
                        ProgressView()
                    } else {
                        Label("Link this robot", systemImage: "link")
                    }
                }
                .disabled(isLinking)
            }
        } header: {
            Text("Robot account")
        } footer: {
            // The LAN hop is plain HTTP and unauthenticated (ADR 0001). Saying so
            // is the honest alternative to implying a security this transport does
            // not have.
            Text("Linking copies your token to the robot over the local network, which is not encrypted. "
                + "Do it on a network you trust.")
        }
        .task {
            guard !previewMode else { return }
            await loadRobotState()
        }
    }

    private var robotAccountText: String {
        guard let robotAccount else { return "…" }
        if robotAccount.isLoggedIn {
            return robotAccount.username.map { "Linked to \($0)" } ?? "Linked"
        }
        return "Not linked"
    }

    private func relayText(_ relay: RelayStatus) -> String {
        switch relay.state {
        case .connected: "Online"
        case .connecting, .reconnecting: "Connecting…"
        case .waitingForToken: "Waiting for a token"
        case .stopped: "Off"
        case .unavailable: relay.message ?? "Not available on this robot"
        case .error: relay.message ?? "Error"
        case let .unknown(state): state
        }
    }

    private func loadRobotState() async {
        robotAccount = try? await session.robotHFAccount()
        relay = try? await session.relayStatus()
    }

    private func link() async {
        guard let token = await model.account.currentToken() else {
            linkError = "This app has no valid token to share. Sign in again."
            return
        }
        isLinking = true
        linkError = nil
        defer { isLinking = false }
        do {
            let refresh = try await session.linkRobot(token: token)
            robotAccount = try? await session.robotHFAccount(refresh: true)
            // `skipped` means no reconnect was started, so waiting for the relay to
            // change state would wait forever — the daemon's own docstring calls
            // that trap out by name.
            relay = refresh.didStart ? try? await session.relayStatus() : relay
        } catch {
            linkError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func unlink() async {
        isLinking = true
        linkError = nil
        defer { isLinking = false }
        do {
            try await session.unlinkRobot()
            robotAccount = try? await session.robotHFAccount(refresh: true)
            relay = try? await session.relayStatus()
        } catch {
            linkError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
