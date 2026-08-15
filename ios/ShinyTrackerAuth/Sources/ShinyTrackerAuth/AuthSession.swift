import AuthenticationServices
import Foundation
import Auth

/// Thrown when the session is gone and cannot be refreshed.
///
/// Mirrors `SessionExpiredError` in `frontend/src/utils/authedFetch.ts` so both clients fail the
/// same way: the caller logs the user out and does not surface a generic network error.
public struct SessionExpiredError: Error, Equatable, CustomStringConvertible {
    public init() {}
    public var description: String { "session_expired" }
}

/// The two web-redirect providers the web app offers (`frontend/src/components/Login.tsx`).
/// Apple is deliberately absent — it is native, see ``AuthSession/prepareAppleRequest(_:)``.
public enum WebSignInProvider: String, Sendable, CaseIterable {
    case github, google
}

/// Owns the Supabase session for the app.
///
/// `@MainActor` observable class rather than an `actor`: every consumer is UI (SwiftUI reads
/// `userID` / `isSessionExpired` during `body`), and the Sign in with Apple request handoff is
/// itself main-actor work. An `actor` would force an `await` hop on every view read and need a
/// `@MainActor` mirror of the same state alongside it. `AuthClient` is already thread-safe and
/// does its own token refresh off this actor.
@MainActor
@Observable
public final class AuthSession {
    /// The Supabase user id — the `sub` claim the Go API turns into `X-User-ID`.
    public private(set) var userID: UUID?

    /// Set when the session could not be refreshed, or when the API client reports a 401 it could
    /// not recover from. Observable: drive the login screen off it.
    public private(set) var isSessionExpired = false

    public var isSignedIn: Bool { userID != nil }

    private let client: AuthClient
    private var appleRawNonce: String?

    public init(config: AuthConfig = .fromBundle()) {
        client = AuthClient(
            url: config.authURL,
            // Same pair SupabaseClient sends; per-request Authorization from the session wins.
            headers: ["Apikey": config.anonKey, "Authorization": "Bearer \(config.anonKey)"],
            flowType: .pkce,
            redirectToURL: AuthConfig.redirectURL,
            localStorage: AuthClient.Configuration.defaultLocalStorage
        )
        // `authStateChanges` always emits `.initialSession` first, so this also restores the
        // Keychain-persisted session on launch.
        Task { [weak self, client] in
            for await (_, session) in client.authStateChanges {
                guard let self else { return }
                self.userID = session?.user.id
                if session != nil { self.isSessionExpired = false }
            }
        }
    }

    /// A valid access token for `Authorization: Bearer …`, refreshed if the current one expired.
    public func currentAccessToken() async throws -> String {
        do {
            return try await client.session.accessToken
        } catch is AuthError {
            // ponytail: any AuthError here means the SDK could not produce a usable session.
            // Transport failures (URLError) propagate unchanged so a flaky network does not sign
            // the user out. Narrow this if GoTrue 5xx ever starts showing up as expiry.
            markSessionExpired()
            throw SessionExpiredError()
        }
    }

    /// Force a token rotation and return the new access token.
    ///
    /// ``currentAccessToken()`` only refreshes when the SDK itself believes the token expired.
    /// When the *server* rejects a token the SDK still considers valid, retrying with the same
    /// cached string is a guaranteed second 401 — so the API client's single 401 retry comes
    /// through here instead. Same error contract as ``currentAccessToken()``: `AuthError` means
    /// expiry, `URLError` propagates untouched.
    public func refreshAccessToken() async throws -> String {
        do {
            return try await client.refreshSession().accessToken
        } catch is AuthError {
            markSessionExpired()
            throw SessionExpiredError()
        }
    }

    /// Call from the API client when a request still returns 401 after a refresh + retry.
    /// Equivalent to the web client's `onSessionExpired` callback.
    public func markSessionExpired() {
        isSessionExpired = true
        userID = nil
    }

    public func signOut() async throws {
        try await client.signOut()
        userID = nil
        isSessionExpired = false
    }

    // MARK: - Sign in with Apple (native)

    /// Pass to `SignInWithAppleButton(onRequest:)`. Sends Apple the *hashed* nonce and keeps the
    /// raw one for ``completeAppleSignIn(_:)``.
    public func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let raw = Nonce.random()
        appleRawNonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = Nonce.sha256Hex(raw)
    }

    /// Pass to `SignInWithAppleButton(onCompletion:)`. Exchanges Apple's identity token for a
    /// Supabase session.
    public func completeAppleSignIn(_ result: Result<ASAuthorization, any Error>) async throws {
        let raw = appleRawNonce
        appleRawNonce = nil

        let authorization = try result.get()
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let rawNonce = raw
        else {
            throw AppleSignInError.missingIdentityToken
        }

        _ = try await client.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
        )
    }

    /// `LocalizedError`, not bare `Error`. A plain Swift error reaches the user through
    /// `localizedDescription`, which bridges via NSError and renders the type name back at them —
    /// "The operation couldn't be completed. (ShinyTrackerAuth.AuthSession.AppleSignInError
    /// error 0.)". `errorDescription` is the hook that replaces that with a sentence.
    public enum AppleSignInError: Error, LocalizedError, Equatable {
        /// Apple returned an authorization without a usable identity token, or the nonce was lost.
        case missingIdentityToken

        public var errorDescription: String? {
            switch self {
            case .missingIdentityToken:
                "Apple didn't return a usable sign-in token. Try signing in again."
            }
        }
    }

    // MARK: - GitHub / Google (ASWebAuthenticationSession)

    /// Opens `ASWebAuthenticationSession` (the SDK's own launch flow) against the provider and
    /// completes PKCE on the `shinytracker://auth-callback` redirect.
    public func signIn(with provider: WebSignInProvider) async throws {
        let supabaseProvider: Provider =
            switch provider {
            case .github: .github
            case .google: .google
            }
        _ = try await client.signInWithOAuth(
            provider: supabaseProvider,
            redirectTo: AuthConfig.redirectURL
        )
    }
}
