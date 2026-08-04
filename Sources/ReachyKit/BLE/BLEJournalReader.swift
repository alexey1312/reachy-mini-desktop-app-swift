import Foundation

/// Reassembles the robot's journal into whole lines.
///
/// `_read_journal` hands back a fixed-size slice of its buffer and **empties what it
/// handed over**, so a line is regularly cut in half between two reads and the first half
/// is already gone. Carrying the tail here rather than in the console means the console
/// and its tests never learn that the transport is lossy in the first place.
public struct BLEJournalReader: Equatable, Sendable {
    private var carry = ""

    public init() {}

    /// The whole lines in this chunk. Anything after the last newline is held back until
    /// the next read finishes it.
    public mutating func ingest(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else { return [] }
        var lines = (carry + chunk).components(separatedBy: "\n")
        carry = lines.removeLast()
        return lines
    }

    /// Whatever is still held back. The feed has stopped, so an unterminated last line is
    /// all there is ever going to be of it.
    public mutating func flush() -> [String] {
        defer { carry = "" }
        return carry.isEmpty ? [] : [carry]
    }
}
