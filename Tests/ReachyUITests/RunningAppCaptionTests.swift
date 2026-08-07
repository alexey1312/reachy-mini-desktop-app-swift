import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

/// What the dock and the sheet *say* about a running app, as opposed to when they
/// say anything at all (`RunningAppModelTests`). Split off because the caption is a
/// pure mapping over a status and a turn — it needs no model, no session and no
/// client — and because the two together no longer fit one file.
@MainActor
@Suite("Running app caption", .timeLimit(.minutes(1)))
struct RunningAppCaptionTests {
    private static let app = RobotApp.previewInstalled[0]
    private static let conversationApp = RobotApp.previewConversation

    private func status(_ state: RobotAppStatus.State, error: String? = nil) -> RobotAppStatus {
        RobotAppStatus(app: Self.app, state: state, error: error)
    }

    @Test("conversation captions use the released semantic vocabulary", arguments: [
        (ConversationTurn.listening, "Listening…"),
        (.thinking, "Thinking…"),
        (.speaking, "Speaking…"),
        (.ready, "Ready"),
        (.unknown("waiting_for_tool"), "waiting_for_tool"),
    ])
    func semanticCaption(turn: ConversationTurn, caption: String) {
        let conversation = RobotAppStatus(app: Self.conversationApp, state: .running)
        #expect(RunningAppCaption.title(of: conversation, conversationTurn: turn) == caption)
    }

    @Test("process transitions and reachability still take precedence")
    func processStatePrecedesConversationTurn() {
        let stopping = RobotAppStatus(app: Self.conversationApp, state: .stopping)
        let running = RobotAppStatus(app: Self.conversationApp, state: .running)

        #expect(RunningAppCaption.title(of: stopping, conversationTurn: .speaking) == "Stopping…")
        #expect(RunningAppCaption.title(
            of: running,
            conversationTurn: .speaking,
            isReachable: false
        ) == "Robot unreachable")
    }

    /// The daemon's `error` is a stderr tail, so a surface that prints it in full
    /// must not also substitute it for the state phrase: the reader gets the same
    /// text twice, and the copy on top is cut off after two lines of traceback.
    /// Only the dock, which has nowhere else to put it, inlines the crash.
    @Test("a crash is inlined in the caption and never in the state phrase")
    func crashStaysOutOfTheStatePhrase() {
        let tail = """
        Process exited with code 1
        Traceback (most recent call last):
        ModuleNotFoundError: No module named 'cv2'
        """
        let crashed = status(.error, error: tail)

        #expect(RunningAppCaption.title(of: crashed) == "Stopped with an error")
        #expect(RunningAppCaption.description(of: crashed) == tail)
    }
}
