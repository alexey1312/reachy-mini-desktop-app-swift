import Foundation
import Observation
import ReachyDesign
import ReachySSH

/// Browsing the robot's own file system over SFTP.
///
/// The screen is thin and this is where the interesting parts live: the two-step
/// host key trust, and the fact that a failure here is *not* a daemon failure and
/// so cannot go through `recordDaemonFailure`.
@MainActor
@Observable
final class RobotFilesModel {
    /// A phone must not pull a multi-gigabyte model file into memory to hand it to
    /// a document picker.
    static let readLimit = 8 * 1024 * 1024

    /// Where the session is, as opposed to what a single operation did.
    enum Phase: Equatable {
        /// Nothing asked yet.
        case idle
        /// No password stored for this robot, or the stored one was refused.
        case needsPassword
        /// First contact. The user has to see this key before it is pinned.
        case confirmHostKey(HostKeyFingerprint)
        /// A pinned robot answered with a different key. Never auto-accepted.
        case hostKeyChanged(pinned: HostKeyFingerprint, offered: HostKeyFingerprint)
        case connecting
        case browsing
        case failed(String)
    }

    /// A destructive action waiting for a confirmation dialog.
    enum Confirmation: Equatable, Identifiable {
        case delete(RemoteFile)

        var id: String {
            switch self {
            case let .delete(file): "delete-\(file.path)"
            }
        }
    }

    private let files: any RobotFileSystem
    private let credentials: any SSHCredentialStore
    private let robot: String
    private let host: String
    private let port: Int

    private(set) var phase: Phase = .idle
    private(set) var path: String
    private(set) var entries: [RemoteFile] = []
    /// A listing in flight over rows already on screen. Distinct from `.connecting`
    /// so a refresh keeps what is there instead of blanking it.
    private(set) var isLoading = false
    /// Never answered yet, as opposed to answered with nothing — without this the
    /// first frame would claim an empty directory before anything was asked.
    private(set) var hasListed = false
    private(set) var lastError: String?
    /// The operation the screen is showing progress for, if any.
    private(set) var transferring: String?

    /// The password field. Not `private(set)`: the sheet binds to it.
    var username: String
    var password: String
    var confirming: Confirmation?

    init(
        files: any RobotFileSystem,
        credentials: any SSHCredentialStore = KeychainSSHCredentialStore(),
        robot: String,
        host: String,
        port: Int = SSHCredentials.defaultPort,
        path: String = "/"
    ) {
        self.files = files
        self.credentials = credentials
        self.robot = robot
        self.host = host
        self.port = port
        self.path = path
        let stored = try? credentials.credentials(forRobot: robot)
        username = stored?.username ?? SSHCredentials.defaultUsername
        password = stored?.password ?? ""
    }

    // MARK: - Places worth a shortcut

    /// The directory the 2026-08-07 incident lived in. A bookmark rather than a
    /// jail: the audience is advanced users, and a path jail is code that can only
    /// ever be wrong about what someone needs to reach.
    static let appsSitePackages = "/venvs/apps_venv/lib/python3.12/site-packages"
    static let home = "/home/pollen"

    // MARK: - Session

    /// Opens the session if it is not open, using whatever password is in hand.
    /// Safe to call from `.task` — a second call while browsing does nothing.
    func start() async {
        guard phase == .idle || phase == .needsPassword else { return }
        guard !password.isEmpty else {
            phase = .needsPassword
            return
        }
        await connect()
    }

    func connect() async {
        phase = .connecting
        lastError = nil
        do {
            try await files.connect(
                SSHCredentials(host: host, port: port, username: username, password: password)
            )
            try? credentials.save(
                SSHCredentials(host: host, port: port, username: username, password: password),
                forRobot: robot
            )
            phase = .browsing
            await refresh()
        } catch let error as ReachySSHError {
            switch error {
            case let .hostKeyUnknown(fingerprint):
                phase = .confirmHostKey(fingerprint)
            case let .hostKeyChanged(pinned, offered):
                phase = .hostKeyChanged(pinned: pinned, offered: offered)
            case .authenticationFailed:
                // Back to the field rather than to a dead end, and the stored
                // password goes: keeping a refused one means the next visit
                // fails the same way with nothing to show for it.
                try? credentials.clear(robot: robot)
                phase = .needsPassword
                lastError = String(localized: .reachy("That password was refused by the robot."))
            default:
                phase = .failed(Self.describe(error))
            }
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Accepts the offered key and connects again. Only reachable from a screen
    /// that showed the fingerprint.
    func trustOfferedKey() async {
        let offered: HostKeyFingerprint? = switch phase {
        case let .confirmHostKey(fingerprint): fingerprint
        case let .hostKeyChanged(_, offered): offered
        default: nil
        }
        guard let offered, let files = files as? SSHFileSystem else {
            // A stub file system has no key to pin; treat acceptance as a retry so
            // previews and tests can drive the same button.
            await connect()
            return
        }
        do {
            try await files.trustOfferedHostKey(offered)
        } catch {
            phase = .failed(Self.describe(error))
            return
        }
        await connect()
    }

    func disconnect() async {
        await files.disconnect()
        phase = .idle
        entries = []
        hasListed = false
    }

    // MARK: - Browsing

    func refresh() async {
        guard phase == .browsing else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await files.list(path).sorted(by: Self.ordered)
            hasListed = true
            lastError = nil
        } catch is CancellationError {
            // Leaving the screen mid-listing learned nothing: it may neither report
            // a failure nor clear one still being read.
        } catch {
            report(error)
        }
    }

    func open(_ file: RemoteFile) async {
        guard file.isDirectory else { return }
        await go(to: file.path)
    }

    func go(to newPath: String) async {
        path = newPath
        entries = []
        hasListed = false
        await refresh()
    }

    func goUp() async {
        guard let parent = RemoteFile.parent(of: path) else { return }
        await go(to: parent)
    }

    var canGoUp: Bool {
        RemoteFile.parent(of: path) != nil
    }

    /// Deepest first, so the trail reads left to right.
    var breadcrumb: [(name: String, path: String)] {
        var trail = [(name: "/", path: "/")]
        var walked = ""
        for component in path.split(separator: "/") {
            walked += "/" + component
            trail.append((name: String(component), path: walked))
        }
        return trail
    }

    // MARK: - Changing things

    /// Reads a file so the screen can hand it to a document picker.
    func contents(of file: RemoteFile) async -> Data? {
        transferring = file.name
        defer { transferring = nil }
        do {
            return try await files.read(file.path, limit: Self.readLimit)
        } catch {
            report(error)
            return nil
        }
    }

    /// Writes to an explicit path. This is both "add a file here" and "replace this
    /// one": without an in-app editor, replacing over the same path is how an edit
    /// made on the device lands back on the robot.
    func upload(_ data: Data, to destination: String) async {
        transferring = (destination as NSString).lastPathComponent
        defer { transferring = nil }
        do {
            try await files.write(data, to: destination)
            await refresh()
        } catch {
            report(error)
        }
    }

    func makeDirectory(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await files.makeDirectory(at: RemoteFile.joining(path, trimmed))
            await refresh()
        } catch {
            report(error)
        }
    }

    func rename(_ file: RemoteFile, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != file.name else { return }
        do {
            try await files.rename(file.path, to: RemoteFile.joining(path, trimmed))
            await refresh()
        } catch {
            report(error)
        }
    }

    func delete(_ file: RemoteFile) async {
        do {
            try await files.remove(file)
            await refresh()
        } catch {
            report(error)
        }
    }

    /// The destination an upload into the current directory would take.
    func destination(forFileNamed name: String) -> String {
        RemoteFile.joining(path, name)
    }

    // MARK: - Errors

    private func report(_ error: any Error) {
        if error is CancellationError {
            return
        }
        lastError = Self.describe(error)
    }

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

    /// Directories first, then case-insensitive by name — the order every file
    /// manager uses, and the one that puts `user_personalities/` above the noise.
    private static func ordered(_ lhs: RemoteFile, _ rhs: RemoteFile) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

#if DEBUG
    extension RobotFilesModel {
        /// In the model's own file rather than in `Previews/`, because it writes
        /// `private(set)` members that `@testable` does not reach.
        static func preview(
            files: any RobotFileSystem = PreviewFileSystem.brokenPersonality(),
            phase: Phase = .browsing,
            path: String = PreviewFileSystem.appPackage,
            entries: [RemoteFile] = [],
            isLoading: Bool = false,
            hasListed: Bool = true,
            error: String? = nil,
            transferring: String? = nil,
            password: String = "root"
        ) -> RobotFilesModel {
            let model = RobotFilesModel(
                files: files,
                credentials: EphemeralCredentialStore(),
                robot: "preview",
                host: "reachy-mini.local",
                path: path
            )
            model.phase = phase
            model.entries = entries
            model.isLoading = isLoading
            model.hasListed = hasListed
            model.lastError = error
            model.transferring = transferring
            model.password = password
            return model
        }

        /// The directory listing the fixture holds, sorted the way the screen shows
        /// it — so a preview is final on its first frame without a `.task`.
        static func previewEntries(at path: String = PreviewFileSystem.appPackage) -> [RemoteFile] {
            PreviewFileSystem.brokenPersonality().entries(at: path).sorted(by: ordered)
        }
    }

    /// Keeps a preview's password out of the real Keychain.
    struct EphemeralCredentialStore: SSHCredentialStore {
        func credentials(forRobot _: String) throws -> SSHCredentials? {
            nil
        }

        func save(_: SSHCredentials, forRobot _: String) throws {}
        func clear(robot _: String) throws {}
    }
#endif
