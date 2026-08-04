/// Whether the Robot section's name field can be edited, and the footer that says why not.
///
/// `POST /api/daemon/robot-name` postdates daemon 1.9.0, which mounts neither verb and
/// answers 404 — so the field is greyed out on such a robot instead of letting the save
/// fail. `RobotSession.supportsRename` carries the handshake's verdict.
struct RobotNameField {
    let isEditable: Bool
    let footer: String

    private static let hardwareIDNote = "The hardware ID never changes."

    init(supportsRename: Bool, daemonVersion: String?) {
        isEditable = supportsRename
        guard !supportsRename else {
            footer = "The name identifies this robot on the network. \(Self.hardwareIDNote)"
            return
        }
        let running = daemonVersion.map { "this robot runs daemon \($0)" } ?? "this robot runs an older one"
        footer = "Renaming needs newer robot software — \(running). \(Self.hardwareIDNote)"
    }
}
