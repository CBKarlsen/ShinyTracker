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
            do {
                try await auth.signOut()
            } catch {
                errorMessage = "Couldn't sign out — \(error.localizedDescription)"
            }
            signingOut = false
        }
    }
}
