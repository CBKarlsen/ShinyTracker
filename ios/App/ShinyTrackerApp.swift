import AuthenticationServices
import ShinyTrackerAPI
import ShinyTrackerAuth
import ShinyTrackerUI
import SwiftUI

@main
struct ShinyTrackerApp: App {
    @State private var auth = AuthSession()

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
                .preferredColorScheme(.dark)
        }
    }
}

/// Signed out shows the sign-in screen; signed in shows the app shell.
struct RootView: View {
    let auth: AuthSession

    var body: some View {
        ZStack {
            ScreenBackground()
            #if DEBUG
            if let fixture = HuntPreview.requested {
                // Debug-only: renders the real Hunt views against canned responses so the design
                // can be checked without a Supabase session. See HuntPreviewHarness.swift.
                AppShell(model: HuntListModel(client: HuntPreview.client(fixture)))
            } else if auth.isSignedIn {
                AppShell(auth: auth)
            } else {
                LoginView(auth: auth)
            }
            #else
            if auth.isSignedIn {
                AppShell(auth: auth)
            } else {
                LoginView(auth: auth)
            }
            #endif
        }
    }
}

/// `background:#060608` with the warm bloom in the top-right corner.
///
/// The prototype's is an ellipse — `radial-gradient(420px 260px at 78% -6%,#1d1a12 0%,transparent
/// 62%)`. This is the circular approximation; at these opacities the difference is not visible.
struct ScreenBackground: View {
    var body: some View {
        Palette.screen.color
            .overlay(
                RadialGradient(
                    colors: [Palette.glow.color, .clear],
                    center: UnitPoint(x: 0.78, y: -0.06),
                    startRadius: 0,
                    endRadius: 260
                )
            )
            .ignoresSafeArea()
    }
}

// MARK: - Shell

/// The four modes. "Each mode owns a colour, so you always know where you are."
///
/// Reference is deliberately absent: it is a search sheet reachable from every header, not a
/// mode — "that keeps the nav at four labelled slots".
enum AppMode: String, CaseIterable, Identifiable {
    case hunt = "Hunt"
    case nuzlocke = "Nuzlocke"
    case dex = "Dex"
    case team = "Team"

    var id: Self { self }

    var accent: Swatch {
        switch self {
        case .hunt: Palette.hunt
        case .nuzlocke: Palette.nuzlocke
        case .dex: Palette.dex
        case .team: Palette.team
        }
    }

    /// System symbols standing in for the prototype's inline SVGs and its shiny-charm PNG.
    var symbol: String {
        switch self {
        case .hunt: "sparkles"
        case .nuzlocke: "list.bullet.rectangle"
        case .dex: "square.split.1x2"
        case .team: "circle.and.line.horizontal"
        }
    }
}

struct AppShell: View {
    @State private var mode: AppMode = .hunt
    @State private var model: HuntListModel

    init(auth: AuthSession) {
        // One client for the session. `APIConfig.fromBundle()` fatalErrors on a missing
        // API_BASE_URL, which is a build-configuration mistake, not a runtime state.
        self.init(model: HuntListModel(client: APIClient(auth: .session(auth))))
    }

    init(model: HuntListModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch mode {
            case .hunt:
                HuntScreen(model: model)
            case .nuzlocke, .dex, .team:
                ModePlaceholder(mode: mode)
            }
            ModeTabBar(mode: $mode)
        }
    }
}

struct ModePlaceholder: View {
    let mode: AppMode

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: mode.symbol)
                .font(.system(size: 26))
                .foregroundStyle(mode.accent.color.opacity(0.55))
            Text(mode.rawValue)
                .font(Typography.emptyTitle)
                .foregroundStyle(Palette.textPrimary.color)
            Text("Not built yet.")
                .font(Typography.emptyBody)
                .foregroundStyle(Palette.textMuted.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab bar

/// The floating bar: four mode pills — the selected one filled in its mode colour and labelled,
/// the rest icon-only — plus the profile tile on the right.
///
/// `padding:6px;border-radius:24px;background:rgba(18,18,26,.82);border:1px solid #2a2a36;
///  backdrop-filter:blur(24px)`
struct ModeTabBar: View {
    @Binding var mode: AppMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppMode.allCases) { candidate in
                pill(candidate)
            }
            profileTile
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: Radii.tabBar)
                .fill(.ultraThinMaterial)                                  // blur(24px)
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.tabBar)
                        .fill(Palette.tabBar.color.opacity(Palette.tabBarOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.tabBar)
                        .strokeBorder(Palette.tabBarBorder.color, lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.9), radius: 17, y: 12)
        .padding(.bottom, 26)
    }

    /// `pill(on, color)`: 40 tall, `padding:0 15px` and auto width when on, a bare 46pt square
    /// when off.
    private func pill(_ candidate: AppMode) -> some View {
        let on = candidate == mode
        return Button {
            mode = candidate
        } label: {
            HStack(spacing: 7) {
                Image(systemName: candidate.symbol).font(.system(size: 15))
                if on {
                    Text(candidate.rawValue).font(Typography.segmentOn)
                }
            }
            .foregroundStyle((on ? Palette.onAccent : Palette.textSecondary).color)
            .frame(height: 40)
            .frame(minWidth: on ? 0 : 46)
            .padding(.horizontal, on ? 15 : 0)
            .background(
                on ? candidate.accent.color : .clear,
                in: .rect(cornerRadius: Radii.pill)
            )
            .contentShape(.rect)
        }
        .accessibilityLabel(candidate.rawValue)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// `linear-gradient(135deg,#26262e,#1a1a24)` with a letter in it. The prototype hardcodes
    /// "T"; there is no profile fetch on this screen, so it is the generic person glyph.
    private var profileTile: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 13))
            .foregroundStyle(Palette.textPrimary.color)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(
                    colors: [Swatch(0x26262E).color, Swatch(0x1A1A24).color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Palette.border.color, lineWidth: 1)
            )
            .padding(.leading, 1)
            .padding(.trailing, 3)
            .accessibilityHidden(true)
    }
}

// MARK: - Sign in

/// Unchanged from the auth phase — the Hunt screen is the redesign, this is not.
struct LoginView: View {
    let auth: AuthSession

    @State private var errorMessage: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 20) {
            Text("ShinyTracker")
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.textPrimary.color)

            SignInWithAppleButton(
                .signIn,
                onRequest: auth.prepareAppleRequest,
                onCompletion: { result in run { try await auth.completeAppleSignIn(result) } }
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)

            Button("Continue with GitHub") { run { try await auth.signIn(with: .github) } }
            Button("Continue with Google") { run { try await auth.signIn(with: .google) } }

            if auth.isSessionExpired {
                Text("Session expired — sign in again.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textMuted.color)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.nuzlocke.color)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .buttonStyle(GoldButtonStyle())
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
