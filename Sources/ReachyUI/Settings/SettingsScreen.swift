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
            recoverySection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { nameDraft = identity?.name ?? "" }
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
                    Label("Recovery over Bluetooth", systemImage: "wrench.and.screwdriver")
                }
                if let developerScreen {
                    NavigationLink {
                        developerScreen()
                    } label: {
                        Label("Developer tools", systemImage: "stethoscope")
                    }
                }
            }
        } footer: {
            Text("For a robot that has dropped off the network. It needs to be within Bluetooth range.")
        }
    }

    private var robotSection: some View {
        Section {
            HStack {
                TextField("Name", text: $nameDraft)
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
                    Button("Save", action: rename)
                        .buttonStyle(.borderless)
                }
            }
            if let renameError {
                Text(renameError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            LabeledContent("Daemon", value: identity?.daemonVersion ?? "—")
            LabeledContent("Connection", value: session.link.displayString)
            if let hardwareID = identity?.hardwareID {
                LabeledContent("Hardware ID", value: hardwareID)
                    .font(.body.monospaced())
            }
        } header: {
            Text("Robot")
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
                renameError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                nameDraft = identity?.name ?? ""
            }
        }
    }
}
