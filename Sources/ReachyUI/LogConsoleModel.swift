import Foundation
import Observation

@MainActor
@Observable
final class LogConsoleModel {
    static let capacities = [1000, 5000, 20000]

    private(set) var entries: [LogEntry] = []
    private(set) var visible: [LogEntry] = []
    private(set) var pending: [LogEntry] = []

    /// Pause freezes the display, never the stream — dropping lines here would punch a
    /// hole in the exported log exactly when the user is watching a failure.
    var paused = false {
        didSet {
            if !paused {
                flush()
            }
        }
    }

    var capacity = 5000 {
        didSet {
            trim()
            recompute()
        }
    }

    var query = "" {
        didSet { recompute() }
    }

    var minimumLevel = LogLevel.debug {
        didSet { recompute() }
    }

    private var nextID = 0

    var isFiltered: Bool {
        !query.isEmpty || minimumLevel != .debug
    }

    var copyText: String {
        visible.map(\.text).joined(separator: "\n")
    }

    var filterSummary: String? {
        guard isFiltered else { return nil }
        var parts = ["level: \(minimumLevel)"]
        if !query.isEmpty {
            parts.append("search: \"\(query)\"")
        }
        return parts.joined(separator: ", ")
    }

    func ingest(_ chunk: String) {
        let appended = chunk.split(separator: "\n", omittingEmptySubsequences: true).map { raw in
            defer { nextID += 1 }
            return LogEntry(id: nextID, raw: String(raw))
        }
        guard !appended.isEmpty else { return }
        if paused {
            pending.append(contentsOf: appended)
            return
        }
        entries.append(contentsOf: appended)
        trim()
        visible.append(contentsOf: appended.filter(matches))
        trimVisible()
    }

    func clear() {
        entries = []
        visible = []
        pending = []
    }

    func export(address: String) -> LogExport {
        LogExport(entries: visible, address: address, totalCount: entries.count, filterSummary: filterSummary)
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        entries.append(contentsOf: pending)
        visible.append(contentsOf: pending.filter(matches))
        pending = []
        trim()
        trimVisible()
    }

    private func trim() {
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// `visible` is a maintained cache, so it must drop the same head `entries` dropped.
    private func trimVisible() {
        guard let oldest = entries.first?.id else {
            visible = []
            return
        }
        let drop = visible.prefix { $0.id < oldest }.count
        if drop > 0 {
            visible.removeFirst(drop)
        }
    }

    private func matches(_ entry: LogEntry) -> Bool {
        entry.level >= minimumLevel && (query.isEmpty || entry.text.localizedCaseInsensitiveContains(query))
    }

    private func recompute() {
        visible = entries.filter(matches)
    }
}
