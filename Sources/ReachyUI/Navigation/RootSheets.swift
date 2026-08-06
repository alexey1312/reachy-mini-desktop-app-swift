import HuggingFaceAuth
import ReachyDesign
import ReachyKit
import SwiftUI

/// The sheets the whole interface shares, mounted once above both the gate and the
/// shell so that connecting — which throws the tree below it away — does not
/// dismiss one mid-flight.
struct RootSheets: ViewModifier {
    let session: RobotSession
    let hfAccount: HFAccount
    let router: ReachyRouter
    let connect: (CentralRobot) -> Void

    func body(content: Content) -> some View {
        @Bindable var router = router
        return content
            .sheet(isPresented: $router.showsAccount) {
                NavigationStack {
                    HFSignInScreen(session: session, model: HFSignInModel(account: hfAccount))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(.reachy("Done")) { router.showsAccount = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $router.showsRemoteRobots) {
                NavigationStack {
                    YourReachiesScreen(
                        model: YourReachiesModel(
                            listing: CentralRelayClient { [hfAccount] in await hfAccount.currentToken() },
                            // `.needsReauth` also carries a username, so the state is
                            // the question, not whether a name is known.
                            isSignedIn: { [hfAccount] in
                                if case .signedIn = hfAccount.state {
                                    true
                                } else {
                                    false
                                }
                            }
                        ),
                        connect: connect,
                        // Pushed inside this sheet rather than sending the user to
                        // the robot's Settings tab: that tab does not exist until a
                        // robot is connected — exactly the case that brings anyone
                        // here.
                        signIn: { HFSignInScreen(session: session, model: HFSignInModel(account: hfAccount)) }
                    )
                }
            }
            .sheet(isPresented: $router.showsPermissions) {
                NavigationStack {
                    // Only a LAN session proves the local network was granted; a relay
                    // session proves the opposite is possible, which is half the reason
                    // this screen is reachable from the gate at all.
                    PermissionsScreen(localNetworkProvenByConnection: isConnectedOverLAN)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(.reachy("Done")) { router.showsPermissions = false }
                            }
                        }
                }
            }
    }

    private var isConnectedOverLAN: Bool {
        switch session.link {
        case .lan: true
        // A relay session proves nothing about the local network, and `.none` proves
        // less — which is the case this sheet is reachable from the gate for.
        case .none, .remote: false
        }
    }
}
