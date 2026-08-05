import Foundation
@testable import HuggingFaceAuth
import ReachyTestSupport
import Testing

@Suite("Hugging Face OAuth", .timeLimit(.minutes(1)))
struct HFOAuthTests {
    private let configuration = HFOAuthConfiguration(
        clientID: "client-1",
        redirectURI: "reachy-mini-swift://oauth-callback",
        scopes: HFOAuthConfiguration.reachyMiniScopes
    )

    // MARK: PKCE

    /// RFC 7636 appendix B, verbatim. The one place a subtle base64 mistake —
    /// padding, or standard alphabet instead of URL-safe — silently produces a
    /// challenge the Hub rejects with nothing but "invalid_grant".
    @Test("derives the challenge the RFC's own vector expects")
    func matchesTheRFCVector() {
        let pkce = HFOAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(pkce.method == "S256")
    }

    @Test("a generated verifier is legal and never repeats")
    func generatesLegalVerifiers() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let first = HFOAuth.PKCE()
        let second = HFOAuth.PKCE()

        #expect(first.verifier != second.verifier)
        for pkce in [first, second] {
            #expect((43 ... 128).contains(pkce.verifier.count))
            #expect(CharacterSet(charactersIn: pkce.verifier).isSubset(of: allowed))
        }
    }

    // MARK: Authorization URL

    /// Built with `URLComponents` (rule 5) — the redirect URI carries a scheme and
    /// slashes, and hand-interpolating it is how it ends up unescaped.
    @Test("the authorize URL carries everything the Hub needs and nothing else")
    func buildsTheAuthorizationURL() throws {
        let pkce = HFOAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = try #require(HFOAuth.authorizationURL(configuration: configuration, pkce: pkce, state: "state-1"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.host == "huggingface.co")
        #expect(url.path == "/oauth/authorize")
        #expect(query["client_id"] == "client-1")
        #expect(query["redirect_uri"] == "reachy-mini-swift://oauth-callback")
        #expect(query["response_type"] == "code")
        #expect(query["state"] == "state-1")
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["scope"] == HFOAuthConfiguration.reachyMiniScopes)
        // A public client has no secret to send, and sending one would be worse
        // than useless — it would be shipped inside the app.
        #expect(query["client_secret"] == nil)
    }

    @Test("an app without a registered client id knows it cannot start")
    func reportsMissingClientID() {
        #expect(HFOAuthConfiguration(clientID: "", redirectURI: "x://y", scopes: "openid").isConfigured == false)
        #expect(configuration.isConfigured)
    }

    // MARK: Callback

    @Test("reads the code out of the callback")
    func readsTheCallbackCode() throws {
        let url = try #require(URL(string: "reachy-mini-swift://oauth-callback?code=abc123&state=state-1"))

        #expect(try HFOAuth.code(in: url, expectedState: "state-1") == "abc123")
    }

    /// The state is the only thing standing between this app and a code somebody
    /// else obtained — dropping the check is the classic OAuth mistake.
    @Test("a callback whose state does not match is refused")
    func refusesAForeignState() throws {
        let url = try #require(URL(string: "reachy-mini-swift://oauth-callback?code=abc123&state=someone-else"))

        #expect(throws: HFOAuthError.stateMismatch) {
            try HFOAuth.code(in: url, expectedState: "state-1")
        }
    }

    @Test("a refusal from the Hub is reported as itself")
    func readsAnErrorCallback() throws {
        let url = try #require(URL(string: "reachy-mini-swift://oauth-callback?error=access_denied&state=state-1"))

        #expect(throws: HFOAuthError.denied("access_denied")) {
            try HFOAuth.code(in: url, expectedState: "state-1")
        }
    }

    // MARK: Token exchange

    private func exchanger(_ stubs: [String: StubURLProtocol.Stub]) -> HFTokenExchanger {
        HFTokenExchanger(configuration: configuration, session: StubURLProtocol.makeSession(stubs))
    }

    @Test("exchanges the code for a token, sending the verifier and no secret")
    func exchangesTheCode() async throws {
        let session = StubURLProtocol.makeSession([
            "/oauth/token": .init(
                statusCode: 200,
                json: #"{"access_token": "hf_abc", "expires_in": 28800, "refresh_token": "r1"}"#
            ),
        ])

        let token = try await HFTokenExchanger(configuration: configuration, session: session)
            .exchange(code: "abc123", verifier: "verifier-1")

        #expect(token.accessToken == "hf_abc")
        #expect(token.refreshToken == "r1")
        #expect(token.expiresAt != nil)

        let body = try #require(StubURLProtocol.bodies(for: session).first)
        let form = try #require(String(bytes: body, encoding: .utf8))
        #expect(form.contains("grant_type=authorization_code"))
        #expect(form.contains("code_verifier=verifier-1"))
        #expect(form.contains("client_id=client-1"))
        #expect(!form.contains("client_secret"))
    }

    /// The Hub answers with `accessToken`, not `access_token`, often enough that
    /// the daemon reads both — so this does too.
    @Test("a camelCase token key is read just the same")
    func readsCamelCaseToken() async throws {
        let token = try await exchanger([
            "/oauth/token": .init(statusCode: 200, json: #"{"accessToken": "hf_abc", "expiresIn": 100}"#),
        ]).exchange(code: "abc123", verifier: "v")

        #expect(token.accessToken == "hf_abc")
    }

    @Test("a refused exchange throws rather than yielding an empty token")
    func reportsRefusedExchange() async {
        let exchanger = exchanger([
            "/oauth/token": .init(statusCode: 400, json: #"{"error": "invalid_grant"}"#),
        ])

        await #expect(throws: HFOAuthError.self) {
            try await exchanger.exchange(code: "abc123", verifier: "v")
        }
    }

    @Test("refreshing sends the refresh token under the right grant")
    func refreshesAToken() async throws {
        let session = StubURLProtocol.makeSession([
            "/oauth/token": .init(statusCode: 200, json: #"{"access_token": "hf_new", "expires_in": 100}"#),
        ])
        let existing = HFToken(accessToken: "hf_old", refreshToken: "r1", expiresAt: .distantPast)

        let token = try await HFTokenExchanger(configuration: configuration, session: session).refreshing(existing)

        #expect(token.accessToken == "hf_new")
        let form = try #require(String(bytes: StubURLProtocol.bodies(for: session).first ?? Data(), encoding: .utf8))
        #expect(form.contains("grant_type=refresh_token"))
        #expect(form.contains("refresh_token=r1"))
    }

    /// A token with no refresh token cannot be renewed — the user has to sign in
    /// again, which through Safari's cookies is one tap.
    @Test("a token that cannot be refreshed says so instead of trying")
    func reportsUnrefreshableToken() async {
        let exchanger = exchanger([:])
        let existing = HFToken(accessToken: "hf_old", refreshToken: nil, expiresAt: .distantPast)

        #expect(existing.needsReauth(at: Date()))
        await #expect(throws: HFOAuthError.notRefreshable) {
            try await exchanger.refreshing(existing)
        }
    }

    // MARK: Personal access tokens

    /// The fallback path, and the only one that works until the OAuth app is
    /// registered. `whoami-v2` is what the daemon and central both validate with.
    @Test("a pasted token is validated against the Hub, not trusted")
    func validatesAPastedToken() async throws {
        let session = StubURLProtocol.makeSession([
            "/api/whoami-v2": .init(statusCode: 200, json: #"{"name": "alexey1312", "type": "user"}"#),
        ])

        let username = try await HFTokenExchanger(configuration: configuration, session: session)
            .username(for: "hf_pasted")

        #expect(username == "alexey1312")
        let request = try #require(StubURLProtocol.requests(for: session).first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer hf_pasted")
        #expect(request.url?.absoluteString.contains("hf_pasted") == false)
    }

    @Test("a token the Hub does not know is refused")
    func rejectsAnInvalidPastedToken() async {
        let exchanger = exchanger(["/api/whoami-v2": .init(statusCode: 401)])

        await #expect(throws: HFOAuthError.invalidToken) {
            try await exchanger.username(for: "nope")
        }
    }
}
