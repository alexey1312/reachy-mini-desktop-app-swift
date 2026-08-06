import CoreTransferable
import Foundation
import ReachyDesign
import UniformTypeIdentifiers

/// Share payload for the visible log. Holds a snapshot array — cheap to rebuild on every
/// toolbar render — and serializes only when the user actually shares.
struct LogExport: Transferable, Sendable {
    let entries: [LogEntry]
    let address: String
    let totalCount: Int
    let filterSummary: String?

    /// UTC so exports from different machines sort together.
    private static let stamp: Date.ISO8601FormatStyle = .iso8601
        .year().month().day()
        .dateSeparator(.omitted)
        .dateTimeSeparator(.standard)
        .time(includingFractionalSeconds: false)
        .timeSeparator(.omitted)

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { export in
            Data(export.text(exportedAt: .now).utf8)
        }
        .suggestedFileName { $0.filename(exportedAt: .now) }
    }

    /// An exported log is read detached from the app, so it has to say what was captured
    /// and whether a filter truncated it.
    func text(exportedAt: Date) -> String {
        var header = """
        # Reachy Mini daemon log
        # robot: \(address)
        # exported: \(exportedAt.formatted(.iso8601))
        # lines: \(entries.count) of \(totalCount)
        """
        if let filterSummary {
            header += String(localized: .reachy(" (\(filterSummary))"))
        }
        return header + "\n" + entries.map(\.text).joined(separator: "\n") + "\n"
    }

    func filename(exportedAt: Date) -> String {
        let host = address.replacingOccurrences(of: ":", with: "-")
        return "reachy-daemon-\(host)-\(exportedAt.formatted(Self.stamp)).txt"
    }
}
