import AuthenticationServices
import ShinyTrackerAPI
import ShinyTrackerAuth
import ShinyTrackerUI
import SwiftUI

@main
struct ShinyTrackerApp: App {
    @State private var auth = AuthSession()

    init() {
        // The default shared URLCache is small enough that a full dex scroll evicts its own
        // sprites. These are tiny immutable PNGs on a CDN, so the disk copy is the cheap win and
        // ``SpriteCache`` sits in front of it holding the decoded images.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }

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
                AppShell(preview: HuntPreview.client(fixture), mode: .hunt)
            } else if let fixture = DexPreview.requested {
                // Same, for the Dex. See DexPreviewHarness.swift.
                AppShell(preview: DexPreview.client(fixture), mode: .dex)
            } else if let fixture = NuzlockePreview.requested {
                // Same, for a run. See NuzlockePreviewHarness.swift.
                AppShell(preview: NuzlockePreview.client(fixture), mode: .nuzlocke)
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: AppMode
    @State private var hunts: HuntListModel
    @State private var library: GameLibraryModel
    @State private var newHunt: NewHuntModel
    @State private var dex: DexModel
    @State private var nuzlocke: NuzlockeModel

    init(auth: AuthSession) {
        // One client for the session, shared by every mode. `APIConfig.fromBundle()`
        // fatalErrors on a missing API_BASE_URL, which is a build-configuration mistake, not a
        // runtime state.
        // The living-dex store is keyed by user id: these ticks live in UserDefaults
        // until the API can hold them, and an unscoped key would show one account
        // another's dex after a sign-out/sign-in on the same device.
        self.init(client: APIClient(auth: .session(auth)), userID: auth.userID)
    }

    /// Every model shares one client — and the new-hunt sheet shares the *library* model with
    /// the Games tab, so a charm toggled there moves the odds in the method step immediately.
    init(client: APIClient, mode: AppMode = .hunt, userID: UUID? = nil) {
        // Exactly one store for the whole session, four keys. Two stores over the same key would
        // race on the temp file an atomic write moves into place — the loser is only a cache miss,
        // but there is no reason to have two when the keys never overlap.
        let snapshots = SnapshotStore(userID: userID)
        let library = GameLibraryModel(client: client, store: snapshots)
        _mode = State(initialValue: mode)
        _hunts = State(initialValue: HuntListModel(client: client, store: snapshots))
        _library = State(initialValue: library)
        _newHunt = State(initialValue: NewHuntModel(client: client, library: library))
        _dex = State(
            initialValue: DexModel(
                client: client, store: .userDefaults(userID: userID), snapshots: snapshots))
        _nuzlocke = State(initialValue: NuzlockeModel(client: client, store: snapshots))
    }

    #if DEBUG
    /// A preview-harness client, whose Dex must not write its living-dex ticks into the
    /// simulator's real `UserDefaults` — and whose canned fixtures must not land in a real
    /// account's snapshot directory, hence the anonymous store.
    init(preview client: APIClient, mode: AppMode) {
        let snapshots = SnapshotStore(userID: nil)
        let dex = DexModel(client: client, store: .ephemeral(), snapshots: snapshots)
        dex.view = DexPreview.initialView ?? .browse
        dex.selectedGameID = DexPreview.initialGameID
        let library = GameLibraryModel(client: client, store: snapshots)
        _mode = State(initialValue: mode)
        _hunts = State(initialValue: HuntListModel(client: client, store: snapshots))
        _library = State(initialValue: library)
        _newHunt = State(initialValue: NewHuntModel(client: client, library: library))
        _dex = State(initialValue: dex)
        _nuzlocke = State(initialValue: NuzlockeModel(client: client, store: snapshots))
    }
    #endif

    var body: some View {
        // safeAreaInset rather than a ZStack overlay: it makes SwiftUI inset the
        // scrollable content by the bar's real measured height, including the home
        // indicator. The ZStack version floated the bar OVER the list and relied on a
        // hand-tuned bottom padding, which under-cleared it — the last card was clipped
        // behind the bar. A measured inset cannot drift when the bar's size changes.
        Group {
            switch mode {
            case .hunt:
                HuntScreen(model: hunts, library: library, newHunt: newHunt)
            case .dex:
                DexScreen(model: dex)
            case .nuzlocke:
                NuzlockeScreen(model: nuzlocke)
            case .team:
                ModePlaceholder(mode: mode)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ModeTabBar(mode: $mode)
        }
        // Counting is offline-first: a tap only reaches a queue on disk. Coming back to the app is
        // the moment most likely to have a network behind it, and it costs one no-op call when the
        // queue is empty. Deliberately the only trigger besides a load — a failed drain waits for
        // the next foreground rather than needing a timer or a reachability observer to watch.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await hunts.drain() }
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
            // Same formatting as the hunt list — see userFacingMessage. Using
            // localizedDescription here silently dropped the real message for the
            // CustomStringConvertible error types this app actually throws.
            do { try await operation() } catch { errorMessage = userFacingMessage(for: error) }
            busy = false
        }
    }
}
