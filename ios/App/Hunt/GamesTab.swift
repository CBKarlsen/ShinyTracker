import Foundation
import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// The owner's game library: which games they have, and the Shiny Charm in each.
///
/// Shared by the Games tab and the new-hunt sheet on purpose — the prototype says the two are
/// one thing ("The Games tab toggles the Shiny Charm, which changes the odds shown in the method
/// step"), so toggling a charm has to move the odds on the next sheet without a round trip.
@MainActor
@Observable
final class GameLibraryModel {
    private(set) var state: LoadState = .loading
    /// Every game the API knows, generation order.
    private(set) var games: [Game] = []
    /// `game_id -> has_shiny_charm`. **Membership is ownership**: a key means the game is in the
    /// library, its value is only the charm flag.
    private(set) var owned: [Int: Bool] = [:]
    /// A failed write, surfaced after the optimistic change has been rolled back.
    private(set) var syncError: String?

    private let client: APIClient
    /// `GET /api/user/{id}/games` 403s unless the id is the caller's own, and this screen has no
    /// `AuthSession` — the preview harness has no session at all. `/api/me` is the id's source.
    private var userID: UUID?

    init(client: APIClient) { self.client = client }

    func load() async {
        state = .loading
        syncError = nil
        do {
            let id = try await resolveUserID()
            async let all = client.games()
            async let mine = client.userGames(userID: id)
            games = try await all.sorted { ($0.generation, $0.id) < ($1.generation, $1.id) }
            // Not `uniqueKeysWithValues`: that TRAPS on a duplicate key. `user_games` is keyed
            // (user_id, game_id) so duplicates should be impossible, and a crash is the wrong
            // way to find out that they were not.
            owned = Dictionary(
                try await mine.map { ($0.gameID, $0.hasShinyCharm) }, uniquingKeysWith: { _, b in b }
            )
            state = .ready
        } catch {
            state = .failed(userFacingMessage(for: error))
        }
    }

    private func resolveUserID() async throws -> UUID {
        if let userID { return userID }
        let id = try await client.me().id
        userID = id
        return id
    }

    // MARK: Reads

    func game(_ id: Int) -> Game? { games.first { $0.id == id } }

    func isOwned(_ gameID: Int) -> Bool { owned[gameID] != nil }

    /// Whether the charm is actually applying to this game's odds.
    ///
    /// The availability check is repeated here even though `ToggleUserGameHandler` rejects a
    /// charm on a pre-B2W2 game: the same belt-and-braces `GetOddsHandler` applies, so a stale
    /// row written before that guard existed can never inflate the odds shown.
    func charmOn(_ gameID: Int) -> Bool { shinyCharmAvailable(gameID) && owned[gameID] == true }

    // MARK: Writes

    func setOwned(_ gameID: Int, _ isOwned: Bool) async {
        let before = owned[gameID]
        owned[gameID] = isOwned ? false : nil
        syncError = nil
        do {
            if isOwned {
                try await client.setUserGame(
                    userID: try resolveUserID(), gameID: gameID,
                    SetUserGameRequest(hasShinyCharm: false)
                )
            } else {
                try await client.removeUserGame(userID: try resolveUserID(), gameID: gameID)
            }
            Haptics.impact(.light)
        } catch {
            owned[gameID] = before
            syncError = "Couldn't update your library. \(userFacingMessage(for: error))"
        }
    }

    func toggleCharm(_ gameID: Int) async {
        guard let before = owned[gameID], shinyCharmAvailable(gameID) else { return }
        owned[gameID] = !before
        syncError = nil
        do {
            try await client.setUserGame(
                userID: try resolveUserID(), gameID: gameID,
                SetUserGameRequest(hasShinyCharm: !before)
            )
            Haptics.impact(.light)
        } catch {
            owned[gameID] = before
            syncError = "Couldn't update the Shiny Charm. \(userFacingMessage(for: error))"
        }
    }
}

/// Mirrors `backend/internal/calc/charm.go` (and `frontend/src/utils/games.ts`, which mirrors it
/// too) — the charm was introduced in Black 2 / White 2 and exists in every mainline game since.
///
/// A list rather than `id >= 8`: `charm.go` is explicit that a newly added game has to be opted
/// in by hand, and `ToggleUserGameHandler` 400s on anything not in it. Guessing on this side
/// would only turn a wrong assumption into a failed write.
func shinyCharmAvailable(_ gameID: Int) -> Bool {
    (8...17).contains(gameID)
}

// MARK: - View

/// The Games tab: the library, and the one rule about it that is not obvious.
struct GamesTab: View {
    let library: GameLibraryModel

    var body: some View {
        switch library.state {
        case .loading:
            ProgressView()
                .tint(Palette.textMuted.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let reason):
            StateBlock(
                symbol: "exclamationmark.triangle",
                title: "Couldn't load your games",
                body: reason
            ) {
                Button("Try again") { Task { await library.load() } }
                    .buttonStyle(GoldButtonStyle())
                    .padding(.top, 22)
            }

        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Verbatim from the prototype. Users assume a charm toggle rewrites the
                    // odds of hunts they are already running; it does not.
                    Text(
                        """
                        Your library sets base odds and whether the Shiny Charm applies. \
                        Tap a game to toggle the charm — changes apply to new hunts; active \
                        hunts keep the odds they started with.
                        """
                    )
                    .font(Typography.meta)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.textMuted.color)
                    .padding(.bottom, 4)

                    if let syncError = library.syncError {
                        Text(syncError)
                            .font(Typography.hint)
                            .foregroundStyle(Palette.danger.color)
                    }

                    ForEach(library.games) { game in
                        row(game)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .refreshable { await library.load() }
        }
    }

    /// `padding:13px 15px;background:#111118;border-radius:16px`, outlined in the accent once the
    /// game is in the library (`inset 0 0 0 1px ${accent}44`).
    private func row(_ game: Game) -> some View {
        let owned = library.isOwned(game.id)
        let charmOn = library.charmOn(game.id)
        let hasCharm = shinyCharmAvailable(game.id)

        return HStack(spacing: 12) {
            // Ownership. Split from the charm tap because they are different edits and the
            // prototype's fixed 6-game library never had to express "I don't own this".
            Button {
                Task { await library.setOwned(game.id, !owned) }
            } label: {
                Image(systemName: owned ? "checkmark" : "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle((owned ? Palette.hunt : Palette.textMuted).color)
                    .frame(width: 34, height: 34)
                    .background(Palette.surfaceRaised.color, in: .rect(cornerRadius: 11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(
                                owned ? Palette.hunt.alpha(0x55) : Palette.border.color,
                                lineWidth: 1
                            )
                    )
                    .contentShape(.rect)
            }
            .accessibilityLabel(
                owned
                    ? "Remove \(game.title) from your library"
                    : "Add \(game.title) to your library"
            )

            Button {
                Task { await library.toggleCharm(game.id) }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(game.title)
                            .font(Typography.listTitle)
                            .foregroundStyle(Palette.textPrimary.color)
                        Text("\(generationLabel(game.generation)) · base 1/\(game.baseOdds.formatted(.number))")
                            .font(Typography.stat)
                            .foregroundStyle(Palette.textMuted.color)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    CharmTag(hasCharm: hasCharm, charmOn: charmOn, dimmed: !owned)
                }
                .contentShape(.rect)
            }
            .disabled(!owned || !hasCharm)
            .accessibilityLabel(charmAccessibility(game, owned: owned, hasCharm: hasCharm, on: charmOn))
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.listCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.listCard)
                .strokeBorder(
                    owned ? Palette.hunt.alpha(0x44) : Palette.hairline.color,
                    lineWidth: 1
                )
        )
    }

    private func charmAccessibility(
        _ game: Game, owned: Bool, hasCharm: Bool, on: Bool
    ) -> String {
        guard hasCharm else { return "\(game.title) has no Shiny Charm" }
        guard owned else { return "\(game.title). Add it to your library to set the Shiny Charm" }
        return "Shiny Charm in \(game.title), currently \(on ? "on" : "off"). Tap to change."
    }
}

/// `Charm on` / `Charm off` / `No charm` — gold when it is actually applying.
struct CharmTag: View {
    let hasCharm: Bool
    let charmOn: Bool
    /// The game is not in the library, so nothing here applies to anything yet.
    var dimmed = false

    var body: some View {
        let color: Swatch =
            !hasCharm || dimmed ? Palette.textFaint : (charmOn ? Palette.hunt : Palette.textMuted)
        return Text(hasCharm ? (charmOn ? "Charm on" : "Charm off") : "No charm")
            .font(Typography.tag)
            .foregroundStyle(color.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.tag)
                    .strokeBorder(
                        hasCharm && !dimmed
                            ? (charmOn ? Palette.hunt.alpha(0x55) : Palette.border.color)
                            : Palette.hairline.color,
                        lineWidth: 1
                    )
            )
            .fixedSize()
    }
}

/// "Gen IV" — the prototype's `g.gen`.
func generationLabel(_ generation: Int) -> String {
    let roman = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
    guard roman.indices.contains(generation) else { return "Gen \(generation)" }
    return "Gen \(roman[generation])"
}
