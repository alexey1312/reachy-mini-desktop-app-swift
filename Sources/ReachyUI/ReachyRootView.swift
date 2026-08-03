import ReachyKit
import SwiftUI

/// Entry point for the shared UI: connection flow → robot control.
public struct ReachyRootView: View {
    @State private var session = RobotSession()

    public init() {}

    public var body: some View {
        switch session.phase {
        case .idle, .connecting:
            ConnectionScreen(session: session)
        case .connected, .unreachable:
            RobotScreen(session: session)
        }
    }
}
