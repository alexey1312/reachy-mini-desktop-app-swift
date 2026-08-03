@testable import ReachyUI
import Testing

@Suite("LogEntry")
struct LogEntryTests {
    @Test("splits the journalctl short-iso prefix from the message")
    func timestampPrefix() {
        let entry = LogEntry(id: 0, raw: "2026-08-03T10:00:00+0000 reachy daemon[1]: ready")

        #expect(entry.timestamp == "2026-08-03T10:00:00+0000")
        #expect(entry.message == "reachy daemon[1]: ready")
        #expect(entry.text == "2026-08-03T10:00:00+0000 reachy daemon[1]: ready")
        #expect(entry.level == .info)
    }

    @Test("keeps the whole line when there is no timestamp prefix")
    func noTimestampPrefix() {
        let entry = LogEntry(id: 1, raw: "starting up")

        #expect(entry.timestamp == nil)
        #expect(entry.message == "starting up")
        #expect(entry.text == "starting up")
    }

    @Test(
        "classifies the level from upper-case tokens",
        arguments: [
            ("2026-08-03T10:00:00+0000 reachy daemon[1]: ERROR boom", LogLevel.error),
            ("2026-08-03T10:00:00+0000 reachy daemon[1]: CRITICAL boom", LogLevel.error),
            ("2026-08-03T10:00:00+0000 reachy daemon[1]: Traceback (most recent call last):", LogLevel.error),
            ("2026-08-03T10:00:00+0000 reachy daemon[1]: WARNING motor hot", LogLevel.warning),
            ("2026-08-03T10:00:00+0000 reachy daemon[1]: DEBUG tick", LogLevel.debug),
            ("2026-08-03T10:00:00+0000 reachy daemon[1]: serving on 8000", LogLevel.info),
            ("2026-08-03T10:00:00+0000 reachy daemon[1]: error rate is low", LogLevel.info),
        ]
    )
    func levels(raw: String, expected: LogLevel) {
        #expect(LogEntry(id: 0, raw: raw).level == expected)
    }

    @Test("levels are ordered for threshold filtering")
    func ordering() {
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.warning < LogLevel.error)
        #expect(LogLevel.error.description == "error")
    }
}
