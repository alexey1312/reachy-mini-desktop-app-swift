import Foundation
@testable import ReachyKit
import Testing

@Suite("SignalingMessage wire format")
struct SignalingMessageTests {
    private func decode(_ json: String) throws -> SignalingMessage {
        try JSONDecoder().decode(SignalingMessage.self, from: Data(json.utf8))
    }

    private func encodeToDictionary(_ message: SignalingMessage) throws -> NSDictionary {
        let data = try JSONEncoder().encode(message)
        return try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    // MARK: - Inbound (server → client)

    @Test func decodesWelcome() throws {
        #expect(try decode(#"{"type":"welcome","peerId":"abc-123"}"#) == .welcome(peerID: "abc-123"))
    }

    @Test func decodesPeerStatusChanged() throws {
        let message = try decode(
            #"{"type":"peerStatusChanged","peerId":"p1","roles":["producer"],"meta":{"name":"reachymini"}}"#
        )
        #expect(message == .peerStatusChanged(peerID: "p1", roles: ["producer"], name: "reachymini"))
    }

    @Test func decodesPeerStatusChangedWithoutMeta() throws {
        let message = try decode(#"{"type":"peerStatusChanged","peerId":"p1","roles":[]}"#)
        #expect(message == .peerStatusChanged(peerID: "p1", roles: [], name: nil))
    }

    @Test func decodesProducerList() throws {
        let message = try decode(
            #"{"type":"list","producers":[{"id":"p1","meta":{"name":"reachymini"}},{"peerId":"p2","meta":{}}]}"#
        )
        #expect(message == .producerList([
            .init(id: "p1", name: "reachymini"),
            .init(id: "p2", name: nil),
        ]))
    }

    @Test func decodesEmptyProducerList() throws {
        #expect(try decode(#"{"type":"list","producers":[]}"#) == .producerList([]))
    }

    @Test func decodesSessionStarted() throws {
        let message = try decode(#"{"type":"sessionStarted","peerId":"p1","sessionId":"s1"}"#)
        #expect(message == .sessionStarted(peerID: "p1", sessionID: "s1"))
    }

    @Test func decodesOffer() throws {
        let message = try decode(
            #"{"type":"peer","sessionId":"s1","sdp":{"type":"offer","sdp":"v=0\r\n"}}"#
        )
        #expect(message == .sdp(sessionID: "s1", type: "offer", sdp: "v=0\r\n"))
    }

    @Test func decodesRemoteIce() throws {
        let message = try decode(
            #"{"type":"peer","sessionId":"s1","ice":{"candidate":"candidate:1","sdpMid":"0","sdpMLineIndex":0}}"#
        )
        #expect(message == .ice(sessionID: "s1", candidate: "candidate:1", sdpMLineIndex: 0, sdpMid: "0"))
    }

    @Test func decodesEndSession() throws {
        #expect(try decode(#"{"type":"endSession","sessionId":"s1"}"#) == .endSession(sessionID: "s1"))
    }

    @Test func decodesError() throws {
        #expect(try decode(#"{"type":"error","details":"boom"}"#) == .error(details: "boom"))
    }

    // MARK: - Robustness

    @Test func unknownTypeThrows() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"type":"totallyNew","stuff":1}"#)
        }
    }

    @Test func peerWithoutSdpOrIceThrows() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"type":"peer","sessionId":"s1"}"#)
        }
    }

    @Test func extraUnknownFieldsAreIgnored() throws {
        let message = try decode(#"{"type":"welcome","peerId":"x","futureField":{"a":1}}"#)
        #expect(message == .welcome(peerID: "x"))
    }

    // MARK: - Outbound (client → server)

    @Test func encodesSetPeerStatus() throws {
        let dict = try encodeToDictionary(.setPeerStatus(roles: ["listener"], name: "ReachyMini Swift"))
        #expect(dict == [
            "type": "setPeerStatus",
            "roles": ["listener"],
            "meta": ["name": "ReachyMini Swift"],
        ] as NSDictionary)
    }

    @Test func encodesListRequest() throws {
        #expect(try encodeToDictionary(.list) == ["type": "list"] as NSDictionary)
    }

    @Test func encodesStartSession() throws {
        let dict = try encodeToDictionary(.startSession(peerID: "p1"))
        #expect(dict == ["type": "startSession", "peerId": "p1"] as NSDictionary)
    }

    @Test func encodesAnswer() throws {
        let dict = try encodeToDictionary(.sdp(sessionID: "s1", type: "answer", sdp: "v=0\r\n"))
        #expect(dict == [
            "type": "peer",
            "sessionId": "s1",
            "sdp": ["type": "answer", "sdp": "v=0\r\n"],
        ] as NSDictionary)
    }

    @Test func encodesLocalIce() throws {
        let dict = try encodeToDictionary(
            .ice(sessionID: "s1", candidate: "candidate:9", sdpMLineIndex: 1, sdpMid: nil)
        )
        #expect(dict == [
            "type": "peer",
            "sessionId": "s1",
            "ice": ["candidate": "candidate:9", "sdpMLineIndex": 1],
        ] as NSDictionary)
    }

    @Test func encodesEndSession() throws {
        let dict = try encodeToDictionary(.endSession(sessionID: "s1"))
        #expect(dict == ["type": "endSession", "sessionId": "s1"] as NSDictionary)
    }
}
