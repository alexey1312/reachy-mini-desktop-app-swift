import SwiftUI
@preconcurrency import WebRTC

/// Renders a remote `RTCVideoTrack` via Metal (`RTCMTLVideoView` / `RTCMTLNSVideoView`).
public struct CameraVideoView {
    private let track: RTCVideoTrack?

    public init(track: RTCVideoTrack?) {
        self.track = track
    }

    public final class Coordinator {
        fileprivate var current: RTCVideoTrack?

        fileprivate func attach(_ track: RTCVideoTrack?, renderer: RTCVideoRenderer) {
            guard track !== current else { return }
            current?.remove(renderer)
            track?.add(renderer)
            current = track
        }

        fileprivate func detach(renderer: RTCVideoRenderer) {
            current?.remove(renderer)
            current = nil
        }
    }
}

#if os(iOS)
    extension CameraVideoView: UIViewRepresentable {
        public func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        public func makeUIView(context _: Context) -> RTCMTLVideoView {
            let view = RTCMTLVideoView()
            view.videoContentMode = .scaleAspectFit
            return view
        }

        public func updateUIView(_ view: RTCMTLVideoView, context: Context) {
            context.coordinator.attach(track, renderer: view)
        }

        public static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
            coordinator.detach(renderer: view)
        }
    }
#else
    extension CameraVideoView: NSViewRepresentable {
        public func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        public func makeNSView(context _: Context) -> RTCMTLNSVideoView {
            RTCMTLNSVideoView()
        }

        public func updateNSView(_ view: RTCMTLNSVideoView, context: Context) {
            context.coordinator.attach(track, renderer: view)
        }

        public static func dismantleNSView(_ view: RTCMTLNSVideoView, coordinator: Coordinator) {
            coordinator.detach(renderer: view)
        }
    }
#endif
