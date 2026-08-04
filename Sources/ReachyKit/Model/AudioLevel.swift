import Foundation

/// One audio level reported by the daemon, for the speaker or the microphone.
///
/// The daemon has no separate notion of microphone *sensitivity* — that is just
/// the input level, so both directions share this shape.
public struct AudioLevel: Sendable, Equatable {
    /// Percent, 0…100. The daemon rejects anything outside that with a 422.
    public let percent: Int
    /// Audio backend the daemon drove, e.g. `pulseaudio`.
    public let platform: String
    /// The sink or source actually being adjusted — worth showing, since a robot
    /// with several devices gives no other hint about which one moved.
    public let device: String

    public init(percent: Int, platform: String, device: String) {
        self.percent = percent
        self.platform = platform
        self.device = device
    }

    init(_ response: Components.Schemas.VolumeResponse) {
        self.init(percent: response.volume, platform: response.platform, device: response.device)
    }
}
