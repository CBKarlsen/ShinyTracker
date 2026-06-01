package calc

// charmAvailableGames lists every game_id where the Shiny Charm item exists.
// The charm was introduced in Black 2/White 2 (id 8) and has been present in
// every mainline game from that point forward. It is absent in all pre-B2W2
// games: GSC (2), RSE (3), FRLG (4), DPPt (5), HGSS (6), and BW (7).
//
// If a new game is added to the games table it must also be added here before
// its charm toggle is exposed to users. Prefer a small set over a schema column
// so no migration is required for existing deployments.
var charmAvailableGames = map[int]bool{
	8:  true, // Black 2 / White 2 (first game with the Shiny Charm)
	9:  true, // X / Y
	10: true, // Omega Ruby / Alpha Sapphire
	11: true, // Sun / Moon
	12: true, // Ultra Sun / Ultra Moon
	13: true, // Let's Go Pikachu / Eevee
	14: true, // Sword / Shield
	15: true, // Brilliant Diamond / Shining Pearl
	16: true, // Legends: Arceus
	17: true, // Scarlet / Violet
}

// ShinyCharmAvailable reports whether the Shiny Charm exists in the given game.
// Returns false for any game_id not in the allow-list.
func ShinyCharmAvailable(gameID int) bool {
	return charmAvailableGames[gameID]
}
