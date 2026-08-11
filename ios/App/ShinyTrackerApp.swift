import AuthenticationServices
import ShinyTrackerAuth
import ShinyTrackerKit
import SwiftUI

@main
struct ShinyTrackerApp: App {
    @State private var auth = AuthSession()

    var body: some Scene {
        WindowGroup {
            LoginView(auth: auth)
        }
    }
}

/// The only screen in this target. Proves the three sign-in paths compile and link; everything
/// else (hunt list, counter, networking) is a later phase.
struct LoginView: View {
    let auth: AuthSession

    @State private var errorMessage: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 20) {
            Text("ShinyTracker").font(.largeTitle.bold())

            if let userID = auth.userID {
                Text("Signed in").font(.headline)
                Text(userID.uuidString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button("Sign out") { run { try await auth.signOut() } }
            } else {
                SignInWithAppleButton(
                    .signIn,
                    onRequest: auth.prepareAppleRequest,
                    onCompletion: { result in run { try await auth.completeAppleSignIn(result) } }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)

                Button("Continue with GitHub") { run { try await auth.signIn(with: .github) } }
                Button("Continue with Google") { run { try await auth.signIn(with: .google) } }
            }

            if auth.isSessionExpired {
                Text("Session expired — sign in again.").font(.footnote)
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(32)
        .buttonStyle(.borderedProminent)
        .disabled(busy)
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        busy = true
        errorMessage = nil
        Task {
            do { try await operation() } catch { errorMessage = error.localizedDescription }
            busy = false
        }
    }
}

// ponytail: one reference to ShinyTrackerKit so the link is real, not just declared.
// Delete when the odds engine gets an actual consumer.
private let linkCheck = ShinyOdds.self
