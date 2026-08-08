import Foundation
import ReachyDesign
import ReachySSH

/// How an SFTP failure becomes a sentence.
///
/// Its own file for the reason `RobotSession+Errors.swift` is: the mapping is the
/// part worth reading on its own, and `RobotFilesModel.swift` was over SwiftLint's
/// 400-line limit with it inlined.
@MainActor
extension RobotFilesModel {
    /// Its own wording rather than `recordDaemonFailure`, for the reason
    /// `OnboardingModel` and `HFSignInModel` keep theirs: none of this is a daemon
    /// call, so `RobotSession.message(for:)` has nothing to say about it.
    static func describe(_ error: any Error) -> String {
        guard let error = error as? ReachySSHError else {
            return error.localizedDescription
        }
        switch error {
        case .notConnected:
            return String(localized: .reachy("Not connected to the robot."))
        case .authenticationFailed:
            return String(localized: .reachy("That password was refused by the robot."))
        case let .pathNotFound(detail):
            return String(localized: .reachy("No such file or folder. \(detail)"))
        case let .notPermitted(detail):
            return String(localized: .reachy("The robot refused permission. \(detail)"))
        case .directoryNotEmpty:
            return String(localized: .reachy("That folder is not empty. Empty it first."))
        case let .fileTooLarge(bytes, limit):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let cap = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            return String(localized: .reachy("That file is \(size). This screen opens files up to \(cap)."))
        case .hostKeyUnknown, .hostKeyChanged:
            return String(localized: .reachy("The robot's identity key needs to be confirmed."))
        case let .keychain(status):
            return String(localized: .reachy("The keychain refused to store the password (\(status))."))
        case let .transport(detail):
            // The robot's or the library's own words, which is why this stays a
            // runtime string rather than becoming a catalogue entry.
            return detail
        }
    }
}
