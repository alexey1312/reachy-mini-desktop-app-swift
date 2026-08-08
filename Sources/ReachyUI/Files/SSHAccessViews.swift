import ReachyDesign
import ReachySSH
import SwiftUI

/// Asks for the robot's SSH password.
///
/// Inline rather than a sheet: the screen has nothing to show behind it, and a
/// model built inside a `.sheet` content closure is silently replaced every time
/// the parent updates — the trap `RootSheets` documents.
struct SSHPasswordForm: View {
    @Bindable var model: RobotFilesModel
    let onConnect: () -> Void

    var body: some View {
        Form {
            Section {
                TextField(.reachy("User"), text: $model.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                SecureField(.reachy("Password"), text: $model.password)
                    .textContentType(.password)
                    .onSubmit(onConnect)
            } header: {
                Text(.reachy("Sign in to the robot"))
            } footer: {
                Text(.reachy(
                    // The comment sits inside the parentheses on purpose: swiftformat
                    // moves `.reachy(` onto a line of its own, and a disable placed
                    // above that call then points at the wrong line.
                    // swiftlint:disable:next line_length
                    "A Reachy Mini Wireless ships with user pollen and password root. Change it on the robot — anyone on this network can reach it."
                ))
            }

            if let error = model.lastError {
                Section {
                    Text(error)
                        .font(Typography.detail)
                        .foregroundStyle(Tone.danger.style)
                }
            }

            Section {
                Button(.reachy("Connect"), action: onConnect)
                    .disabled(model.password.isEmpty || model.username.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}

/// Trust on first use, and the far more serious case of a key that changed.
///
/// One view for both because the fingerprint block is the same and the difference
/// is entirely in what the screen is willing to say about it.
struct HostKeyConfirmation: View {
    enum Situation: Equatable {
        case firstContact(HostKeyFingerprint)
        case changed(pinned: HostKeyFingerprint, offered: HostKeyFingerprint)
    }

    let situation: Situation
    let onTrust: () -> Void

    var body: some View {
        Form {
            Section {
                Text(offered.groupedForDisplay)
                    .font(Typography.consoleLine)
                    .textSelection(.enabled)
                LabeledContent(.reachy("Algorithm"), value: offered.algorithm)
            } header: {
                Text(.reachy("Robot identity key"))
            } footer: {
                Text(footer)
            }

            if case let .changed(pinned, _) = situation {
                Section {
                    Text(pinned.groupedForDisplay)
                        .font(Typography.consoleLine)
                        .textSelection(.enabled)
                } header: {
                    Text(.reachy("Key you trusted before"))
                }
            }

            Section {
                Button(trustTitle, action: onTrust)
                    .foregroundStyle(isChange ? Tone.danger.style : AnyShapeStyle(.tint))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isChange ? .reachy("Identity changed") : .reachy("New robot"))
    }

    private var isChange: Bool {
        if case .changed = situation {
            return true
        }
        return false
    }

    private var offered: HostKeyFingerprint {
        switch situation {
        case let .firstContact(fingerprint): fingerprint
        case let .changed(_, offered): offered
        }
    }

    private var trustTitle: LocalizedStringResource {
        isChange ? .reachy("Trust the new key") : .reachy("Trust this robot")
    }

    private var footer: LocalizedStringResource {
        if isChange {
            .reachy(
                // swiftlint:disable:next line_length
                "This robot answered with a different key than the one you trusted. Reflashing does that — so does someone impersonating it. Continue only if you know which."
            )
        } else {
            .reachy(
                // swiftlint:disable:next line_length
                "First time connecting to this robot over SSH. To be certain, compare the key with ssh-keygen -lf on the robot."
            )
        }
    }
}
