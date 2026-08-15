import ShinyTrackerAuth
import ShinyTrackerUI
import SwiftUI

/// Account and sign-out. Deliberately minimal: the shiny-charm toggles stay in the Games tab,
/// where the new-hunt sheet already reads them from the same `GameLibraryModel`.
///
/// This screen exists because the app had no way to sign out at all — the old bar's profile tile
/// was decoration with no button behind it.
struct YouScreen: View {
    let auth: AuthSession?

    @State private var signingOut = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            ScreenBackground()
            List {
                Section("Account") {
                    LabeledContent("Signed in as", value: accountLabel)
                }
                Section {
                    Button(role: .destructive) {
                        signOut()
                    } label: {
                        if signingOut {
                            ProgressView()
                        } else {
                            Text("Sign out")
                        }
                    }
                    .disabled(auth == nil || signingOut)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// The user id is all the client holds — there is no profile fetch on this screen, and
    /// `GET /api/me` returns a username the shell does not currently load.
    private var accountLabel: String {
        auth?.userID?.uuidString ?? "Not signed in"
    }

    private func signOut() {
        guard let auth else { return }
        signingOut = true
        errorMessage = nil
        Task {
            // Before the sign-out, not after: a Live Activity outlives the app process and the
            // session, so a card left running would keep this account's hunt on the Lock Screen —
            // with a working `+` — for the next person to use the phone.
            await HuntActivityBridge.endAll()
            do {
                try await auth.signOut()
            } catch {
                // `userFacingMessage`, not `localizedDescription`: `APIError` and
                // `SessionExpiredError` conform to `CustomStringConvertible`, not
                // `LocalizedError`, so `localizedDescription` silently degrades them to the
                // generic "operation couldn't be completed". Same reason `LoginView` routes
                // through it.
                if let message = userFacingMessage(for: error) {
                    errorMessage = "Couldn't sign out — \(message)"
                }
            }
            signingOut = false
        }
    }
}
