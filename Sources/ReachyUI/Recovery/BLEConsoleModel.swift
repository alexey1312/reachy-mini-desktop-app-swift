import Foundation
import Observation
import ReachyKit

/// Drives the recovery console: link to a robot over Bluetooth, tail its journal, and run
/// the scripts that put it back on a network.
///
/// It scans and unlocks on its own rather than borrowing a `RobotSession`, because the
/// robot it exists for is by definition one no `RobotSession` can reach.
@MainActor
@Observable
final class BLEConsoleModel {
    /// The robot's buffer fills at the daemon's own pace, so an empty reply means nothing
    /// happened rather than that we should ask harder.
    private static let activePoll: Duration = .milliseconds(500)
    private static let idlePoll: Duration = .milliseconds(1500)
    /// How many times to respawn a journal that keeps dying before saying so. A robot
    /// whose `journalctl` will not stay up is not going to be argued out of it.
    private static let journalRestarts = 3

    enum Stage: Equatable {
        case scanning
        case connecting
        /// Linked. The journal reads without the code; the scripts do not.
        case locked
        case unlocked
    }

    private(set) var stage: Stage = .scanning
    private(set) var scripts: [BLERecoveryScript] = []
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// Set when the journal feed itself stopped, which the console has to say out loud —
    /// a frozen tail otherwise reads as a quiet robot.
    private(set) var journalFailure: String?
    let log = LogConsoleModel()

    var pinInput = ""

    private let link: BLELink
    private var journalTask: Task<Void, Never>?
    /// Held while a script is being dispatched. The pump serialises anyway; this only
    /// keeps a queued poll from sitting in front of the write.
    private var suspended = false

    init(link: (@MainActor () -> BLELink)? = nil) {
        self.link = link?() ?? BLELink()
    }

    // MARK: - Derived state

    var availability: BLEAvailability {
        link.availability
    }

    var discovered: [BLEPeripheralSnapshot] {
        link.discovered
    }

    var hardwareID: String? {
        link.hardwareID
    }

    var attemptsBeforeLockout: Int {
        link.pin.attemptsBeforeLockout
    }

    var canSubmitPIN: Bool {
        !isBusy && pinInput.count == BLEPinSession.length
    }

    // MARK: - Link

    func startScan() {
        stage = .scanning
        errorMessage = nil
        if !link.startScan() {
            errorMessage = link.lastError
        }
    }

    func connect(to id: UUID) async {
        stage = .connecting
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        guard await link.connect(to: id) else {
            errorMessage = link.lastError
            stage = .scanning
            return
        }
        link.stopScan()
        stage = .locked
        // Both of these read without a code. The journal because a robot too broken to
        // unlock is exactly the one whose log is worth reading, and the script list
        // because it is a plain characteristic — so the screen can say what the code is
        // *for* instead of asking for it in front of an empty page.
        scripts = await link.availableScripts()
        startJournal()
    }

    @discardableResult
    func submitPIN() async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        guard await link.authenticate(pinInput) else {
            errorMessage = link.lastError
            return false
        }
        pinInput = ""
        stage = .unlocked
        return true
    }

    // MARK: - Scripts

    /// Dispatches a script and drops back to locked, because the robot clears its own
    /// session on any `CMD_*` whether the script worked or not.
    func run(_ script: BLERecoveryScript) async {
        suspended = true
        defer { suspended = false }
        log.ingest("--- dispatched \(script.name) ---")
        await link.run(script)
        stage = .locked
    }

    /// Re-sends the code immediately before dispatching, so a session opened five minutes
    /// ago for something harmless cannot carry a destructive script through with it.
    func runGuarded(_ script: BLERecoveryScript, code: String) async -> Bool {
        pinInput = code
        guard await submitPIN() else { return false }
        await run(script)
        return true
    }

    /// Liveness during a software reset, when nothing richer can be asked.
    func isAnswering() async -> Bool {
        await link.isAnswering()
    }

    func stop() {
        journalTask?.cancel()
        journalTask = nil
        pinInput = ""
        Task { [link] in await link.stopJournal() }
        link.stop()
    }

    /// Starts the feed again after it died. Offered as a button because the robot's own
    /// `journalctl` exits for reasons this side cannot see or fix.
    func restartJournal() {
        journalFailure = nil
        startJournal()
    }

    /// Polls the journal until the screen goes away.
    ///
    /// The robot hands back a slice of its buffer cut wherever the window fell and empties
    /// what it hands over, so the reader carries the partial tail between polls and the
    /// console only ever sees whole lines.
    ///
    /// A read answering `Journal not running` is expected rather than terminal: the
    /// robot's GLib watch removes itself the moment `journalctl` closes its pipe, and a
    /// fresh `JOURNAL_START` respawns it. Only a start that will not take is a failure —
    /// and even then the lines already collected stay on screen.
    private func startJournal() {
        journalTask?.cancel()
        journalTask = Task { [weak self] in
            guard let self else { return }
            guard await link.startJournal() else {
                journalFailure = link.lastError
                return
            }
            var reader = BLEJournalReader()
            var interval = Self.activePoll
            var restarts = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                if suspended {
                    continue
                }
                guard let chunk = await link.readJournal() else {
                    guard restarts < Self.journalRestarts, await link.startJournal() else {
                        journalFailure = link.lastError
                        return
                    }
                    restarts += 1
                    interval = Self.idlePoll
                    continue
                }
                let lines = reader.ingest(chunk)
                interval = lines.isEmpty ? Self.idlePoll : Self.activePoll
                guard !lines.isEmpty else { continue }
                restarts = 0
                log.ingest(lines.joined(separator: "\n"))
            }
        }
    }
}

#if DEBUG
    extension BLEConsoleModel {
        /// A console already linked to a robot. No journal is polled: `startJournal` is
        /// private and only reached through `connect`, which a preview never calls.
        static func preview(
            stage: Stage,
            link: BLELink = .preview(),
            scripts: [BLERecoveryScript] = BLERecoveryScript.parse(
                "RESTART_DAEMON, HOTSPOT, WIFI_RESET, SOFTWARE_RESET"
            ),
            errorMessage: String? = nil,
            journalFailure: String? = nil,
            log lines: [String] = []
        ) -> BLEConsoleModel {
            let model = BLEConsoleModel(link: { link })
            model.stage = stage
            model.scripts = scripts
            model.errorMessage = errorMessage
            model.journalFailure = journalFailure
            for line in lines {
                model.log.ingest(line)
            }
            return model
        }
    }
#endif
