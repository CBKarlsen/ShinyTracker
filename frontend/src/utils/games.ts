/**
 * Shiny Charm availability by game ID.
 *
 * Mirrors backend/internal/calc/charm.go — keep in sync when games are added.
 *
 * The Shiny Charm was introduced in Black 2 / White 2 (game ID 8) and
 * exists in every mainline game from that point on.  It does NOT exist in
 * Gen 1–4 or plain Black / White (game IDs 1–7).
 */
export const CHARM_AVAILABLE_GAME_IDS = new Set([
	8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
]);

/**
 * Returns true when the Shiny Charm is obtainable in the given game.
 * Pass `null` / `undefined` when game_id is unknown — returns false so we
 * never accidentally inflate odds.
 */
export function shinyCharmAvailable(gameId: number | null | undefined): boolean {
	if (gameId == null) return false;
	return CHARM_AVAILABLE_GAME_IDS.has(gameId);
}
