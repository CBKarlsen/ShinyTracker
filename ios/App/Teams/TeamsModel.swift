import Foundation
import ShinyTrackerAPI
import SwiftUI

/// Saved Scarlet/Violet teams.
///
/// Reads are cached through `SnapshotStore` so a cold launch draws something before the
/// network answers, matching `HuntListModel` and `DexModel`. Writes are online-only in
/// this slice — see the plan's "teams do NOT use WriteQueue" note. A team that cannot be
/// edited without signal is a smaller failure than a hunt that cannot be counted, and
/// extending `PendingWrite` means migrating the one file that holds unsent encounters.
@MainActor
@Observable
final class TeamsModel {
    private(set) var state: LoadState = .loading
    private(set) var teams: [Team] = []
    private(set) var syncError: String?

    private let client: APIClient
    private let store: SnapshotStore

    init(client: APIClient, store: SnapshotStore) {
        self.client = client
        self.store = store
    }

    func load() async { await load(quiet: false) }
    func refresh() async { await load(quiet: true) }

    /// See `HuntListModel.appear()`.
    func appear() async {
        state == .ready ? await refresh() : await load()
    }

    private func load(quiet: Bool) async {
        syncError = nil
        if !quiet, state != .ready, let cached = await store.load([Team].self, as: .teams) {
            teams = cached
            state = .ready
        }
        if !quiet, state != .ready { state = .loading }
        do {
            let fresh = try await client.teams()
            teams = fresh
            state = .ready
            await store.save(fresh, as: .teams)
        } catch {
            if let message = userFacingMessage(for: error) {
                if quiet || state == .ready {
                    syncError = "Couldn't refresh your teams. \(message)"
                } else {
                    state = .failed(message)
                }
            }
        }
    }

    /// Creates a new team, or replaces an existing one's members wholesale.
    func save(id: UUID?, name: String, members: [TeamMember]) async {
        syncError = nil
        do {
            let saved: Team
            if let id {
                saved = try await client.updateTeam(id: id, UpdateTeamRequest(name: name, members: members))
                if let index = teams.firstIndex(where: { $0.id == id }) {
                    teams[index] = saved
                } else {
                    teams.insert(saved, at: 0)
                }
            } else {
                saved = try await client.createTeam(CreateTeamRequest(name: name, members: members))
                teams.insert(saved, at: 0)
            }
            await store.save(teams, as: .teams)
        } catch {
            if let message = userFacingMessage(for: error) {
                syncError = "Couldn't save the team. \(message)"
            }
        }
    }

    func delete(_ id: UUID) async {
        let before = teams
        teams.removeAll { $0.id == id }
        syncError = nil
        do {
            try await client.deleteTeam(id: id)
            await store.save(teams, as: .teams)
        } catch {
            teams = before
            if let message = userFacingMessage(for: error) {
                syncError = "Couldn't delete the team. \(message)"
            }
        }
    }
}
