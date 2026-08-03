import Foundation
import Observation
import ReachyKit
@preconcurrency import WebRTC

#if os(iOS)
    import AVFAudio
#else
    import AVFoundation
#endif

/// Owns one WebRTC session to the robot: consumes `CameraSignalingClient`
/// events, answers the robot's offer, and exposes the remote video track plus
/// a mic toggle (client mic → robot speaker; the robot's offer is sendrecv).
///
/// Self-healing: any failure (ICE, watchdog, socket) drops the peer connection
/// and forces the signaling client to reconnect, which re-negotiates a session.
@MainActor
@Observable
public final class CameraSession {
    public enum Phase: Equatable, Sendable {
        case connecting
        /// Signaling is up but the daemon has no media producer (sim before acquire).
        case waitingForProducer
        case streaming
        case failed(String)
    }

    public private(set) var phase: Phase = .connecting
    public private(set) var videoTrack: RTCVideoTrack?
    public private(set) var isMicEnabled = false

    /// Not `.streaming` for this long after an offer → drop and re-negotiate (upstream value).
    private static let streamTimeout: Duration = .seconds(10)

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    private let signaling: CameraSignalingClient
    private let connection: RobotConnection?
    private var peerConnection: RTCPeerConnection?
    private var delegateAdapter: PeerConnectionDelegateAdapter?
    private var micTrack: RTCAudioTrack?
    private var eventsTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private struct LocalCandidate {
        var sdp: String
        var sdpMLineIndex: Int32
        var sdpMid: String?
    }

    /// Local candidates gathered before the answer went out (gst requires answer first).
    private var pendingLocalCandidates: [LocalCandidate] = []
    private var answerSent = false

    public init(address: RobotAddress) throws {
        signaling = try CameraSignalingClient(address: address)
        connection = try? RobotConnection(address: address)
    }

    public func start() {
        guard eventsTask == nil else { return }
        configureAudioSession()
        eventsTask = Task { [signaling, connection] in
            // Sim registers no producer until media is acquired; harmless elsewhere.
            try? await connection?.acquireMedia()
            for await event in await signaling.events() {
                await handle(event)
            }
        }
    }

    public func stop() {
        eventsTask?.cancel()
        eventsTask = nil
        teardownPeer()
        phase = .connecting
        let signaling = signaling
        Task { await signaling.disconnect() } // best-effort endSession; ws close also suffices
    }

    public func setMicEnabled(_ enabled: Bool) {
        guard enabled else {
            isMicEnabled = false
            micTrack?.isEnabled = false
            return
        }
        Task {
            guard await Self.requestMicPermission() else { return }
            isMicEnabled = true
            micTrack?.isEnabled = true
        }
    }

    // MARK: - Signaling events

    private func handle(_ event: CameraSignalingClient.Event) async {
        switch event {
        case .waitingForProducer:
            if phase != .streaming {
                phase = .waitingForProducer
            }
        case let .offer(_, sdp):
            await accept(offerSDP: sdp)
        case let .remoteCandidate(_, candidate, sdpMLineIndex, sdpMid):
            // Late-candidate errors are expected once ICE is connected — ignore (upstream does too).
            try? await peerConnection?.add(
                RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            )
        case .sessionEnded:
            teardownPeer()
            phase = .connecting
        }
    }

    private func accept(offerSDP: String) async {
        teardownPeer()
        phase = .connecting

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = [RTCIceServer(urlStrings: [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302",
        ])]
        let adapter = PeerConnectionDelegateAdapter(owner: self)
        guard let peer = Self.factory.peerConnection(
            with: configuration, constraints: Self.noConstraints, delegate: adapter
        ) else {
            phase = .failed("Could not create peer connection")
            return
        }
        delegateAdapter = adapter
        peerConnection = peer

        do {
            try await peer.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: offerSDP))
            attachMicTrack(to: peer)
            let answer = try await peer.answer(for: Self.noConstraints)
            try await peer.setLocalDescription(answer)
            await signaling.send(answerSDP: answer.sdp)
            answerSent = true
            for candidate in pendingLocalCandidates {
                await signaling.send(
                    candidate: candidate.sdp,
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sdpMid: candidate.sdpMid
                )
            }
            pendingLocalCandidates = []
        } catch {
            phase = .failed(error.localizedDescription)
            teardownPeer()
            return
        }
        startWatchdog()
    }

    // MARK: - Peer connection callbacks (from the delegate adapter)

    func handleLocalCandidate(sdp: String, sdpMLineIndex: Int32, sdpMid: String?) {
        guard answerSent else {
            pendingLocalCandidates.append(LocalCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid))
            return
        }
        let signaling = signaling
        Task { await signaling.send(candidate: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid) }
    }

    func handleRemote(videoTrack: RTCVideoTrack) {
        self.videoTrack = videoTrack
        phase = .streaming
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    /// ICE failed or the stream never arrived: drop everything and force the
    /// signaling socket closed — its reconnect loop negotiates a fresh session.
    func restartSession() {
        teardownPeer()
        phase = .connecting
        let signaling = signaling
        Task { await signaling.disconnect() }
    }

    // MARK: - Internals

    private func attachMicTrack(to peer: RTCPeerConnection) {
        // ponytail: the mic track is attached even while muted — gst webrtcsink
        // doesn't renegotiate consumer sessions, so audio must be in the answer
        // from the start. Verified: the OS permission prompt still fires only on
        // the first unmute (WebRTC doesn't start capture for a disabled track).
        let source = Self.factory.audioSource(with: Self.noConstraints)
        let track = Self.factory.audioTrack(with: source, trackId: "reachy-mic")
        track.isEnabled = isMicEnabled
        if let transceiver = peer.transceivers.first(where: { $0.mediaType == .audio }) {
            transceiver.sender.track = track
            transceiver.setDirection(.sendRecv, error: nil)
        }
        micTrack = track
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task {
            guard await (try? Task.sleep(for: Self.streamTimeout)) != nil else { return }
            if phase != .streaming {
                restartSession()
            }
        }
    }

    private func teardownPeer() {
        watchdogTask?.cancel()
        watchdogTask = nil
        peerConnection?.close()
        peerConnection = nil
        delegateAdapter = nil
        micTrack = nil
        videoTrack = nil
        answerSent = false
        pendingLocalCandidates = []
    }

    private static var noConstraints: RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    }

    private func configureAudioSession() {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker])
            try? session.setActive(true)
        #endif
    }

    private static func requestMicPermission() async -> Bool {
        #if os(iOS)
            await AVAudioApplication.requestRecordPermission()
        #else
            await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }
}

/// Bridges nonisolated WebRTC delegate callbacks onto the MainActor session.
private final class PeerConnectionDelegateAdapter: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    private weak var owner: CameraSession?

    init(owner: CameraSession) {
        self.owner = owner
    }

    func peerConnection(_: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let sdp = candidate.sdp
        let index = candidate.sdpMLineIndex
        let mid = candidate.sdpMid
        Task { @MainActor [owner] in
            owner?.handleLocalCandidate(sdp: sdp, sdpMLineIndex: index, sdpMid: mid)
        }
    }

    func peerConnection(_: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams _: [RTCMediaStream]) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        Task { @MainActor [owner] in
            owner?.handleRemote(videoTrack: track)
        }
    }

    func peerConnection(_: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard newState == .failed else { return }
        Task { @MainActor [owner] in
            owner?.restartSession()
        }
    }

    // Required by the protocol; nothing to do. The "data" channel the robot
    // opens is deliberately unused in this iteration.
    func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}
    func peerConnection(_: RTCPeerConnection, didAdd _: RTCMediaStream) {}
    func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}
    func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}
    func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}
    func peerConnection(_: RTCPeerConnection, didOpen _: RTCDataChannel) {}
}
