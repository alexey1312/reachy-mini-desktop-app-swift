import Foundation

/// One entry in a directory on the robot.
///
/// Deliberately free of every Citadel type, so a screen, a preview and a test all
/// speak the same values and only ``SSHFileSystem`` ever sees an SFTP message.
public struct RemoteFile: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case file
        case directory
        case symlink
        /// A socket, a device node, a FIFO. Listed, never opened.
        case other
    }

    public var id: String {
        path
    }

    public let name: String
    public let path: String
    public let kind: Kind
    public let size: UInt64?
    public let modified: Date?
    /// The POSIX mode as the server sent it, for the permissions column.
    public let mode: UInt32?

    public init(
        name: String,
        path: String,
        kind: Kind,
        size: UInt64? = nil,
        modified: Date? = nil,
        mode: UInt32? = nil
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
        self.mode = mode
    }

    public var isDirectory: Bool {
        kind == .directory
    }

    /// SFTP carries no field for the kind of thing an entry is: it lives in the
    /// high bits of the mode, the same `S_IFMT` bits `stat(2)` reports. A server
    /// that sends no permissions at all leaves only `longname`, whose first
    /// character is the one from `ls -l`.
    public static func kind(mode: UInt32?, longname: String) -> Kind {
        guard let mode else {
            switch longname.first {
            case "d": return .directory
            case "l": return .symlink
            case "-": return .file
            default: return .other
            }
        }
        switch mode & 0o170000 {
        case 0o040000: return .directory
        case 0o120000: return .symlink
        case 0o100000: return .file
        default: return .other
        }
    }

    /// `drwxr-xr-x`, built from the mode rather than taken from `longname` — the
    /// latter is the server's own rendering and varies between implementations.
    public static func permissionsText(mode: UInt32?, kind: Kind) -> String? {
        guard let mode else { return nil }
        let prefix: Character = switch kind {
        case .directory: "d"
        case .symlink: "l"
        case .file: "-"
        case .other: "?"
        }
        let bits = ["r", "w", "x"]
        var text = String(prefix)
        for shift in [6, 3, 0] {
            let triad = (mode >> UInt32(shift)) & 0o7
            for (index, bit) in bits.enumerated() {
                text += triad & UInt32(0o4 >> index) != 0 ? bit : "-"
            }
        }
        return text
    }
}

public extension RemoteFile {
    /// Joins a directory to a child name without doubling the separator, which
    /// `"/"` — the one path where the parent already ends in one — otherwise does.
    static func joining(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// The parent of a path, or nil at the root. Trailing slashes are ignored so
    /// that `/a/b/` and `/a/b` answer the same thing.
    static func parent(of path: String) -> String? {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard trimmed != "/", let slash = trimmed.lastIndex(of: "/") else { return nil }
        return slash == trimmed.startIndex ? "/" : String(trimmed[trimmed.startIndex ..< slash])
    }
}
