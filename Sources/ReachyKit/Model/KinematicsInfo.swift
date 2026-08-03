import Foundation

/// Answer of `GET /api/kinematics/info`.
///
/// The daemon nests the payload under an `info` key and spells one field with a
/// space in it, so the mapping is written out rather than synthesised.
public struct KinematicsInfo: Sendable, Equatable, Decodable {
    public let engine: String
    public let checksCollisions: Bool

    /// Only the Placo engine computes the Stewart platform's passive joints; the
    /// default analytical engine leaves them null in the state stream, which is
    /// why this client works them out itself.
    public var providesPassiveJoints: Bool {
        engine.caseInsensitiveCompare("Placo") == .orderedSame
    }

    public init(engine: String, checksCollisions: Bool) {
        self.engine = engine
        self.checksCollisions = checksCollisions
    }

    private enum RootKeys: String, CodingKey {
        case info
    }

    private enum InfoKeys: String, CodingKey {
        case engine
        case checksCollisions = "collision check"
    }

    public init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let info = try root.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        engine = try info.decode(String.self, forKey: .engine)
        checksCollisions = try info.decodeIfPresent(Bool.self, forKey: .checksCollisions) ?? false
    }
}
