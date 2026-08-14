package main

import "testing"

// TestGameDexMapping guards the game -> dex-slug table: every game title is
// present exactly once with at least one non-empty, non-duplicated dex slug.
// Titles must match games.title exactly — the seeder resolves game_id from
// them, and a typo would abort the run rather than mis-seed, but this catches
// the duplicate/empty cases earlier and without a database.
func TestGameDexMapping(t *testing.T) {
	wantTitles := []string{
		"Gold/Silver/Crystal", "Ruby/Sapphire/Emerald", "FireRed/LeafGreen",
		"Diamond/Pearl/Platinum", "HeartGold/SoulSilver", "Black/White",
		"Black 2/White 2", "X/Y", "Omega Ruby/Alpha Sapphire", "Sun/Moon",
		"Ultra Sun/Ultra Moon", "Let's Go Pikachu/Eevee", "Sword/Shield",
		"Brilliant Diamond/Shining Pearl", "Legends: Arceus", "Scarlet/Violet",
	}

	seen := map[string]bool{}
	for _, g := range gameDexes {
		if seen[g.Title] {
			t.Errorf("game %q appears more than once in gameDexes", g.Title)
		}
		seen[g.Title] = true

		if len(g.Dexes) == 0 {
			t.Errorf("game %q has no dex slugs", g.Title)
		}

		slugSeen := map[string]bool{}
		for order, slug := range g.Dexes {
			if slug == "" {
				t.Errorf("game %q has an empty dex slug at order %d", g.Title, order)
			}
			if slugSeen[slug] {
				t.Errorf("game %q lists dex slug %q more than once", g.Title, slug)
			}
			slugSeen[slug] = true
		}
	}

	for _, title := range wantTitles {
		if !seen[title] {
			t.Errorf("missing expected game %q in gameDexes", title)
		}
	}
}
