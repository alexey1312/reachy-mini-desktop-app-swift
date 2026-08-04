import Foundation

/// The half of the link that exists for a robot which is not on the network and may not
/// be able to get there: read its journal, and run the scripts that put it back.
public extension BLELink {
    /// Asks the robot to start tailing its own daemon journal into a buffer.
    ///
    /// It answers the same way whether it started one or already had one, so calling this
    /// twice is harmless — which matters, because a link that drops takes the robot's
    /// journal process with it.
    @discardableResult
    func startJournal() async -> Bool {
        do {
            _ = try await pump.send(.journalStart).value()
            return true
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    /// One poll of the journal buffer.
    ///
    /// The reply is a raw slice cut wherever the robot's fixed-size window fell, so it
    /// routinely begins or ends mid-line — run it through `BLEJournalReader`. The robot
    /// **empties what it hands over**, so anything lost to the read size is lost for good;
    /// the LAN journal is the authoritative one.
    func readJournal() async -> String? {
        do {
            return try await pump.send(.journalRead).value()
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    func stopJournal() async {
        _ = try? await pump.send(.journalStop).value()
    }

    /// Whether the robot's Bluetooth service is still answering.
    ///
    /// Liveness, not progress: that service is its own systemd unit outside `/venvs`, so
    /// it keeps answering right through a software reset. During those minutes it is the
    /// only thing that can be asked anything at all — every richer command goes through
    /// the daemon, which is what is being rebuilt.
    func isAnswering() async -> Bool {
        await ((try? pump.send(.ping)) ?? .failure(.daemonUnreachable)) == .pong
    }

    /// The scripts this robot actually has, read from the characteristic rather than
    /// assumed: it is a listing of a real directory that a later release can add to.
    func availableScripts() async -> [BLERecoveryScript] {
        do {
            let raw = try await transport.read(.availableCommands)
            guard let text = String(bytes: raw, encoding: .utf8) else { return [] }
            return BLERecoveryScript.parse(text)
        } catch {
            lastError = Self.message(for: error)
            return []
        }
    }

    /// Dispatches a recovery script. There is nothing to await and nothing to check.
    ///
    /// The robot's handler returns `None` on success, so its reply encoder crashes and the
    /// GATT write reports an error for a script that ran perfectly. It also clears its own
    /// authentication flag in a `finally`, which is why the PIN session is dropped here
    /// too: the next privileged command needs the code again either way.
    func run(_ script: BLERecoveryScript) async {
        _ = try? await pump.send(.runScript(script.name))
        pin.invalidate()
    }
}
