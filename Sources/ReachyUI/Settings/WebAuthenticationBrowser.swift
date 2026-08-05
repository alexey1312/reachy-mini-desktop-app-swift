import AuthenticationServices
import Foundation
import HuggingFaceAuth

/// The real browser behind `HFWebAuthenticating`.
///
/// `ASWebAuthenticationSession` rather than a `WKWebView` or Safari: it runs the
/// sign-in page **in Safari's own context**, so a user already signed in to the
/// Hub is one tap from done — and this app never sees the page, the password, or
/// the cookies. It is also the only presentation Apple accepts for third-party
/// sign-in.
@MainActor
final class WebAuthenticationBrowser: NSObject, HFWebAuthenticating {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let error {
                    // The user closing the sheet is the one "failure" that is not
                    // one; everything else is worth showing.
                    let isCancellation = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: isCancellation ? HFSignInModel.Cancelled() : error)
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: HFOAuthError.missingCode)
                    return
                }
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = self
            // Deliberately *not* ephemeral: sharing Safari's cookies is the whole
            // reason this is one tap rather than a password prompt.
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

extension WebAuthenticationBrowser: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(macOS)
                NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #else
                let scene = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
                return scene?.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }
}
