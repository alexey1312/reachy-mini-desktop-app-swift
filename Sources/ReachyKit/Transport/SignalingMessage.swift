import Foundation

/// Wire messages of the gst-plugins-rs `webrtcsink` signaling protocol
/// (plain `ws://<host>:8443`, no TLS — see docs/research/webrtc.md).
///
/// The robot is the offerer; this client answers. Unknown message types throw
/// on decode and the caller drops the frame (the daemon may add types anytime).
enum SignalingMessage: Equatable, Sendable {
    struct Producer: Equatable, Sendable {
        var id: String
        var name: String?
    }

    case welcome(peerID: String)
    case setPeerStatus(roles: [String], name: String?)
    case peerStatusChanged(peerID: String, roles: [String], name: String?)
    /// Outbound producer-list request; the server's reply decodes as `.producerList`.
    case list
    case producerList([Producer])
    case startSession(peerID: String)
    case sessionStarted(peerID: String, sessionID: String)
    case sdp(sessionID: String, type: String, sdp: String)
    case ice(sessionID: String, candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    case endSession(sessionID: String)
    case error(details: String)
}

extension SignalingMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, peerId, roles, meta, producers, sessionId, sdp, ice, details
    }

    private struct Meta: Codable {
        var name: String?
    }

    private struct SDPPayload: Codable {
        var type: String
        var sdp: String
    }

    private struct ICEPayload: Codable {
        var candidate: String
        var sdpMLineIndex: Int32
        var sdpMid: String?
    }

    /// The server names producers `id`; `peerId` is accepted too (upstream lib does both).
    private struct ProducerPayload: Codable {
        var id: String?
        var peerId: String?
        var meta: Meta?
    }

    // Flat wire-protocol switches: one branch per message type, no logic to extract.
    // swiftlint:disable:next cyclomatic_complexity
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "welcome":
            self = try .welcome(peerID: container.decode(String.self, forKey: .peerId))
        case "setPeerStatus":
            self = try .setPeerStatus(
                roles: container.decodeIfPresent([String].self, forKey: .roles) ?? [],
                name: container.decodeIfPresent(Meta.self, forKey: .meta)?.name
            )
        case "peerStatusChanged":
            self = try .peerStatusChanged(
                peerID: container.decode(String.self, forKey: .peerId),
                roles: container.decodeIfPresent([String].self, forKey: .roles) ?? [],
                name: container.decodeIfPresent(Meta.self, forKey: .meta)?.name
            )
        case "list":
            if let payloads = try container.decodeIfPresent([ProducerPayload].self, forKey: .producers) {
                self = .producerList(payloads.compactMap { payload in
                    (payload.id ?? payload.peerId).map { Producer(id: $0, name: payload.meta?.name) }
                })
            } else {
                self = .list
            }
        case "startSession":
            self = try .startSession(peerID: container.decode(String.self, forKey: .peerId))
        case "sessionStarted":
            self = try .sessionStarted(
                peerID: container.decode(String.self, forKey: .peerId),
                sessionID: container.decode(String.self, forKey: .sessionId)
            )
        case "peer":
            let sessionID = try container.decode(String.self, forKey: .sessionId)
            if let sdp = try container.decodeIfPresent(SDPPayload.self, forKey: .sdp) {
                self = .sdp(sessionID: sessionID, type: sdp.type, sdp: sdp.sdp)
            } else if let ice = try container.decodeIfPresent(ICEPayload.self, forKey: .ice) {
                self = .ice(
                    sessionID: sessionID,
                    candidate: ice.candidate,
                    sdpMLineIndex: ice.sdpMLineIndex,
                    sdpMid: ice.sdpMid
                )
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container, debugDescription: "peer message without sdp or ice"
                )
            }
        case "endSession":
            self = try .endSession(sessionID: container.decode(String.self, forKey: .sessionId))
        case "error":
            self = try .error(details: container.decode(String.self, forKey: .details))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "unknown message type \(other)"
            )
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .welcome(peerID):
            try container.encode("welcome", forKey: .type)
            try container.encode(peerID, forKey: .peerId)
        case let .setPeerStatus(roles, name):
            try container.encode("setPeerStatus", forKey: .type)
            try container.encode(roles, forKey: .roles)
            try container.encode(Meta(name: name), forKey: .meta)
        case let .peerStatusChanged(peerID, roles, name):
            try container.encode("peerStatusChanged", forKey: .type)
            try container.encode(peerID, forKey: .peerId)
            try container.encode(roles, forKey: .roles)
            try container.encode(Meta(name: name), forKey: .meta)
        case .list:
            try container.encode("list", forKey: .type)
        case let .producerList(producers):
            try container.encode("list", forKey: .type)
            try container.encode(
                producers.map { ProducerPayload(id: $0.id, peerId: nil, meta: Meta(name: $0.name)) },
                forKey: .producers
            )
        case let .startSession(peerID):
            try container.encode("startSession", forKey: .type)
            try container.encode(peerID, forKey: .peerId)
        case let .sessionStarted(peerID, sessionID):
            try container.encode("sessionStarted", forKey: .type)
            try container.encode(peerID, forKey: .peerId)
            try container.encode(sessionID, forKey: .sessionId)
        case let .sdp(sessionID, type, sdp):
            try container.encode("peer", forKey: .type)
            try container.encode(sessionID, forKey: .sessionId)
            try container.encode(SDPPayload(type: type, sdp: sdp), forKey: .sdp)
        case let .ice(sessionID, candidate, sdpMLineIndex, sdpMid):
            try container.encode("peer", forKey: .type)
            try container.encode(sessionID, forKey: .sessionId)
            try container.encode(
                ICEPayload(candidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid),
                forKey: .ice
            )
        case let .endSession(sessionID):
            try container.encode("endSession", forKey: .type)
            try container.encode(sessionID, forKey: .sessionId)
        case let .error(details):
            try container.encode("error", forKey: .type)
            try container.encode(details, forKey: .details)
        }
    }
}
