import ReachyDesign
import ReachyKit
import SwiftUI

/// Everything about the connected robot that is a setting rather than a control.
///
/// Audio used to be a section of `RobotScreen` and a sheet of its own on the Live
/// tab; both now open this, so there is one place to look.
///
/// The Hugging Face account is deliberately *not* here any more. It outlives every
/// connection and is needed before one — signing in is what makes the remote robot
/// list exist — so it sits in the navigation bar instead, robot or no robot.
/// Linking a robot to that account went with it: both halves of the custody story
/// belong on one screen, and splitting them was how "signing out does not unlink"
/// stopped being visible.
struct SettingsScreen: View {
    let session: RobotSession

    @State private var nameDraft = ""
    @State private var isRenaming = false
    @State private var renameError: String?
    @FocusState private var nameFocused: Bool
    /// The app target's own screen, if it has one. Nothing in this package knows
    /// what it contains.
    @Environment(\.reachyDeveloperScreen) private var developerScreen

    private var identity: RobotIdentity? {
        switch session.phase {
        case let .connected(identity), let .unreachable(identity): identity
        default: nil
        }
    }

    var body: some View {
        Form {
            robotSection
            if session.isBackendRunning {
                AudioSettingsSection(session: session)
            }
            if session.supportsWirelessFeatures {
                SystemUpdateCard(session: session)
            }
            if session.canConfigureWiFi {
                WiFiSettingsCard(session: session)
            }
            if session.canPerformMaintenance {
                MaintenanceCard(session: session)
            }
            diagnosticsSection
            privacySection
            recoverySection
        }
        .formStyle(.grouped)
        .navigationTitle(.reachy("Settings"))
        .onAppear { nameDraft = identity?.name ?? "" }
    }

    /// The daemon's journal, moved off the robot screen: it answers "what is the
    /// robot doing" the way the rest of this screen's lower half does, and it is not
    /// a control. It stays out of the Advanced group below, whose contents all need
    /// the robot to be within Bluetooth range — this one needs the opposite.
    @ViewBuilder
    private var diagnosticsSection: some View {
        if session.canReadDaemonLogs {
            Section {
                NavigationLink {
                    LogConsoleScreen(session: session)
                } label: {
                    Label(.reachy("Daemon logs"), systemImage: "terminal")
                }
            }
        }
    }

    /// Above Advanced rather than in it: everything in that group needs the robot
    /// within Bluetooth range, and this needs no robot at all. The same screen is
    /// reachable from the connection gate, which is where someone whose permissions
    /// are the reason they cannot get this far will find it.
    ///
    /// A LAN link is proof the local network was granted — the daemon cannot be
    /// reached without it — and a relay session is proof of nothing, which is the
    /// case worth being able to see.
    private var privacySection: some View {
        Section {
            NavigationLink {
                PermissionsScreen(localNetworkProvenByConnection: isConnectedOverLAN)
            } label: {
                Label(.reachy("Privacy"), systemImage: "hand.raised")
            }
        }
    }

    private var isConnectedOverLAN: Bool {
        switch session.link {
        case .lan: true
        case .none, .remote: false
        }
    }

    /// Collapsed, and last. Everything behind it talks to the robot over Bluetooth
    /// instead of the network, which is only ever what you want when the network has
    /// stopped working.
    private var recoverySection: some View {
        Section {
            DisclosureGroup("Advanced") {
                NavigationLink {
                    BLEConsoleScreen()
                } label: {
                    Label(.reachy("Recovery over Bluetooth"), systemImage: "wrench.and.screwdriver")
                }
                if let developerScreen {
                    NavigationLink {
                        developerScreen()
                    } label: {
                        Label(.reachy("Developer tools"), systemImage: "stethoscope")
                    }
                }
            }
        } footer: {
            Text(.reachy("For a robot that has dropped off the network. It needs to be within Bluetooth range."))
        }
    }

    private var robotSection: some View {
        Section {
            HStack {
                TextField(.reachy("Name"), text: $nameDraft)
                    .focused($nameFocused)
                    .autocorrectionDisabled()
                    .onSubmit { rename() }
                    .disabled(!nameField.isEditable)
                    // A `Form` row does not grey a disabled `TextField` out on its own,
                    // and the footer alone reads as a note rather than as a locked field.
                    .foregroundStyle(nameField.isEditable ? Color.primary : Color.secondary)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                if isRenaming {
                    ProgressView().controlSize(.small)
                } else if canRename {
                    Button(.reachy("Save"), action: rename)
                        .buttonStyle(.borderless)
                }
            }
            if let renameError {
                Text(renameError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            LabeledContent(.reachy("Daemon"), value: identity?.daemonVersion ?? "—")
            LabeledContent(.reachy("Connection"), value: session.link.displayString)
            if let hardwareID = identity?.hardwareID {
                LabeledContent(.reachy("Hardware ID"), value: hardwareID)
                    .font(.body.monospaced())
            }
        } header: {
            Text(.reachy("Robot"))
        } footer: {
            Text(nameField.footer)
        }
    }

    private var nameField: RobotNameField {
        RobotNameField(supportsRename: session.supportsRename, daemonVersion: identity?.daemonVersion)
    }

    private var canRename: Bool {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return nameField.isEditable && !trimmed.isEmpty && trimmed != identity?.name && !isRenaming
    }

    private func rename() {
        guard canRename else { return }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        nameFocused = false
        isRenaming = true
        renameError = nil
        Task {
            defer { isRenaming = false }
            do {
                // The daemon may store something other than what was sent, so the
                // field follows what came back rather than what was typed.
                nameDraft = try await session.rename(to: name)
            } catch {
                renameError.recordDaemonFailure(error)
                nameDraft = identity?.name ?? ""
            }
        }
    }
}
