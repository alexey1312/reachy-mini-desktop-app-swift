import Foundation
@testable import ReachyUI
import Testing

@MainActor
@Suite("LogExport")
struct LogExportTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    @Test("copy text is the visible log without a header")
    func copyText() {
        let model = LogConsoleModel()
        model.ingest("boot ok\nERROR boom")
        model.minimumLevel = .error

        #expect(model.copyText == "ERROR boom")
    }

    @Test("export text opens with a header and carries every visible line")
    func exportText() {
        let model = LogConsoleModel()
        model.ingest("boot ok\nERROR boom")

        let text = model.export(address: "10.42.0.1:8000").text(exportedAt: epoch)

        #expect(text.hasPrefix("# Reachy Mini daemon log\n# robot: 10.42.0.1:8000\n"))
        #expect(text.contains("# exported: 1970-01-01T00:00:00Z"))
        #expect(text.contains("# lines: 2 of 2\n"))
        #expect(text.contains("boot ok"))
        #expect(text.hasSuffix("ERROR boom\n"))
    }

    @Test("header records the filter that truncated the export")
    func filteredHeader() {
        let model = LogConsoleModel()
        model.ingest("boot ok\nERROR boom")
        model.minimumLevel = .error

        let text = model.export(address: "reachy-mini.local").text(exportedAt: epoch)

        #expect(text.contains("# lines: 1 of 2 (level: error)"))
        #expect(!text.contains("boot ok"))
    }

    @Test("file name carries the host and a sortable UTC stamp")
    func filename() {
        let export = LogExport(entries: [], address: "10.42.0.1:8000", totalCount: 0, filterSummary: nil)

        #expect(export.filename(exportedAt: epoch) == "reachy-daemon-10.42.0.1-8000-19700101T000000.txt")
    }
}
