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

        // The last-resort route for the Lock Screen's `+`. Installed here rather than beside the
        // hunt list because *here* is the only code that is guaranteed to run: pressing that
        // button on a killed app has iOS launch the process to perform the intent, and the view
        // tree that builds `AppShell` — and with it `HuntListModel` — may never be evaluated.
        // `LiveHuntCounter` only reaches this after the model has declined, so it can never be
        // writing the queue file behind a model that holds the same queue in memory.
        LiveHuntCounter.shared.fallback = { huntID, step in
            await LiveHuntFallback.count(huntID, by: step)
        }
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
            } else if let fixture = TeamsPreview.requested {
                // Same, for a team. See TeamsPreviewHarness.swift.
                AppShell(preview: TeamsPreview.client(fixture), mode: .teams)
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

/// `background:#060608`, flat.
///
/// The prototype blooms a warm ellipse out of the top-right corner
/// (`radial-gradient(420px 260px at 78% -6%,#1d1a12 0%,transparent 62%)`). Dropped: it decorated
/// nothing, it sat under every screen in the app, and a corner glow is the single most recognisable
/// tell of a generated interface. The gold belongs on the hunt, not on the wallpaper.
struct ScreenBackground: View {
    var body: some View {
        Palette.screen.ignoresSafeArea()
    }
}

// MARK: - Shell

/// The modes. "Each mode owns a colour, so you always know where you are."
///
/// Reference is deliberately absent: it is a search sheet reachable from every header, not a
/// mode — "that keeps the nav at labelled slots".
enum AppMode: String, CaseIterable, Identifiable {
    case hunt = "Hunt"
    case nuzlocke = "Nuzlocke"
    case dex = "Dex"
    case teams = "Teams"
    case you = "You"

    var id: Self { self }

    var accent: Color {
        switch self {
        case .hunt: Palette.hunt
        case .nuzlocke: Palette.nuzlocke
        case .dex: Palette.dex
        case .teams: Palette.team
        // No mode colour of its own — the You tab is chrome, not a hunting mode.
        case .you: Palette.dex
        }
    }

    /// System symbols standing in for the prototype's inline SVGs.
    var symbol: String {
        switch self {
        case .hunt: "sparkles"
        case .nuzlocke: "list.bullet.rectangle"
        case .dex: "square.split.1x2"
        // Six cells, which is what a team is.
        case .teams: "square.grid.3x2"
        case .you: "person.crop.circle"
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
    @State private var teams: TeamsModel
    /// The Teams screens fetch their own reference data — the species list, the item list and one
    /// species' Scarlet/Violet learnset — none of which belongs in ``TeamsModel``, whose job is the
    /// saved teams. So the shell keeps the client it already builds rather than a fifth model.
    private let client: APIClient
    /// Only the You tab needs it, and only to sign out. Optional because the three DEBUG
    /// preview harnesses construct a shell with no session at all.
    private let auth: AuthSession?

    init(auth: AuthSession) {
        // One client for the session, shared by every mode. `APIConfig.fromBundle()`
        // fatalErrors on a missing API_BASE_URL, which is a build-configuration mistake, not a
        // runtime state.
        // The living-dex store is keyed by user id: these ticks live in UserDefaults
        // until the API can hold them, and an unscoped key would show one account
        // another's dex after a sign-out/sign-in on the same device.
        // Leaves the user id where a *background* launch can find it. That launch has no session
        // restored when the Lock Screen's `+` fires, and the write queue is stored per user, so
        // without this the durable route would not know which directory to append to.
        LiveHuntFallback.rememberUser(auth.userID)
        self.init(client: APIClient(auth: .session(auth)), userID: auth.userID, auth: auth)
    }

    /// Every model shares one client — and the new-hunt sheet shares the *library* model with
    /// the Games tab, so a charm toggled there moves the odds in the method step immediately.
    init(client: APIClient, mode: AppMode = .hunt, userID: UUID? = nil, auth: AuthSession? = nil) {
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
        _teams = State(initialValue: TeamsModel(client: client, store: snapshots))
        self.client = client
        self.auth = auth
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
        _teams = State(initialValue: TeamsModel(client: client, store: snapshots))
        self.client = client
        self.auth = nil
    }
    #endif

    // A real TabView, not a hand-drawn bar: it renders in Liquid Glass on the iOS 26 SDK,
    // insets its own content (which is what the old safeAreaInset was compensating for), and
    // minimizes on scroll. `selection` is the same @State the switch used, so the DEBUG
    // preview harnesses that pass an initial mode still work unchanged.
    var body: some View {
        TabView(selection: $mode) {
            Tab(AppMode.hunt.rawValue, systemImage: AppMode.hunt.symbol, value: AppMode.hunt) {
                HuntScreen(model: hunts, library: library, newHunt: newHunt)
            }
            Tab(AppMode.nuzlocke.rawValue, systemImage: AppMode.nuzlocke.symbol, value: AppMode.nuzlocke) {
                NuzlockeScreen(model: nuzlocke)
            }
            Tab(AppMode.dex.rawValue, systemImage: AppMode.dex.symbol, value: AppMode.dex) {
                DexScreen(model: dex)
            }
            Tab(AppMode.teams.rawValue, systemImage: AppMode.teams.symbol, value: AppMode.teams) {
                TeamsScreen(model: teams, client: client)
            }
            Tab(AppMode.you.rawValue, systemImage: AppMode.you.symbol, value: AppMode.you) {
                YouScreen(auth: auth)
            }
        }
        // The selected tab keeps its mode colour — native chrome, not generic chrome.
        .tint(mode.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            LiveHuntAccessory(model: hunts) { mode = .hunt }
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
                .foregroundStyle(Palette.textPrimary)

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
                    .foregroundStyle(Palette.textMuted)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.nuzlocke)
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
