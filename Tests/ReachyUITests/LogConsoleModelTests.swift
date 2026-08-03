@testable import ReachyUI
import Testing

@MainActor
@Suite("LogConsoleModel")
struct LogConsoleModelTests {
    @Test("splits a chunk into lines with increasing ids")
    func ingestChunk() {
        let model = LogConsoleModel()

        model.ingest("one\ntwo\n")
        model.ingest("three")

        #expect(model.entries.map(\.message) == ["one", "two", "three"])
        #expect(model.entries.map(\.id) == [0, 1, 2])
        #expect(model.visible.count == 3)
    }

    @Test("trims the oldest lines at capacity")
    func trimsAtCapacity() {
        let model = LogConsoleModel()
        model.capacity = 3

        model.ingest("one\ntwo\nthree\nfour\nfive")

        #expect(model.entries.map(\.message) == ["three", "four", "five"])
        #expect(model.visible.map(\.message) == ["three", "four", "five"])
    }

    @Test("lowering capacity trims immediately")
    func lowerCapacity() {
        let model = LogConsoleModel()
        model.ingest("one\ntwo\nthree")

        model.capacity = 2

        #expect(model.entries.map(\.message) == ["two", "three"])
        #expect(model.visible.map(\.message) == ["two", "three"])
    }

    @Test("clear empties every buffer")
    func clearBuffers() {
        let model = LogConsoleModel()
        model.ingest("one\ntwo")

        model.clear()

        #expect(model.entries.isEmpty)
        #expect(model.visible.isEmpty)
    }

    @Test("pause buffers lines instead of dropping them")
    func pauseBuffers() {
        let model = LogConsoleModel()
        model.ingest("one")

        model.paused = true
        model.ingest("two\nthree")

        #expect(model.entries.map(\.message) == ["one"])
        #expect(model.pending.map(\.message) == ["two", "three"])
        #expect(model.visible.map(\.message) == ["one"])
    }

    @Test("resume appends pending lines in arrival order")
    func resumeFlushes() {
        let model = LogConsoleModel()
        model.ingest("one")
        model.paused = true
        model.ingest("two\nthree")

        model.paused = false

        #expect(model.entries.map(\.message) == ["one", "two", "three"])
        #expect(model.visible.map(\.message) == ["one", "two", "three"])
        #expect(model.pending.isEmpty)
    }

    @Test("clear also drops pending lines")
    func clearDropsPending() {
        let model = LogConsoleModel()
        model.paused = true
        model.ingest("one")

        model.clear()

        #expect(model.pending.isEmpty)
    }

    @Test("level threshold narrows the visible set")
    func levelFilter() {
        let model = LogConsoleModel()
        model.ingest("boot ok\nWARNING motor hot\nERROR boom")

        model.minimumLevel = .warning

        #expect(model.visible.map(\.message) == ["WARNING motor hot", "ERROR boom"])
        #expect(model.entries.count == 3)
        #expect(model.isFiltered)
    }

    @Test("search matches case-insensitively and combines with the level")
    func searchFilter() {
        let model = LogConsoleModel()
        model.ingest("motor ready\nWARNING Motor hot\nWARNING antenna hot")

        model.query = "motor"

        #expect(model.visible.map(\.message) == ["motor ready", "WARNING Motor hot"])

        model.minimumLevel = .warning

        #expect(model.visible.map(\.message) == ["WARNING Motor hot"])
    }

    @Test("new lines respect the active filter")
    func filterAppliesToIncoming() {
        let model = LogConsoleModel()
        model.minimumLevel = .error

        model.ingest("boot ok\nERROR boom")

        #expect(model.visible.map(\.message) == ["ERROR boom"])
    }

    @Test("resumed lines respect the active filter")
    func filterAppliesToPending() {
        let model = LogConsoleModel()
        model.minimumLevel = .error
        model.paused = true
        model.ingest("boot ok\nERROR boom")

        model.paused = false

        #expect(model.entries.count == 2)
        #expect(model.visible.map(\.message) == ["ERROR boom"])
    }

    @Test("clearing the filter restores the full buffer")
    func resetFilter() {
        let model = LogConsoleModel()
        model.ingest("boot ok\nERROR boom")
        model.query = "boom"

        model.query = ""

        #expect(model.visible.count == 2)
        #expect(!model.isFiltered)
        #expect(model.filterSummary == nil)
    }

    @Test("filter summary describes the active filter")
    func summary() {
        let model = LogConsoleModel()
        model.minimumLevel = .warning
        model.query = "motor"

        #expect(model.filterSummary == "level: warning, search: \"motor\"")
    }
}
