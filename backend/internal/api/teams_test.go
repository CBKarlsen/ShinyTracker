package api

import "testing"

func TestStatPointsValid(t *testing.T) {
	cases := []struct {
		name string
		sp   map[string]int
		want bool
	}{
		{"empty is fine", map[string]int{}, true},
		{"exactly 66 total", map[string]int{"atk": 32, "spe": 32, "hp": 2}, true},
		{"67 is over the pool", map[string]int{"atk": 32, "spe": 32, "hp": 3}, false},
		{"33 in one stat", map[string]int{"atk": 33}, false},
		{"32 in one stat is the cap", map[string]int{"atk": 32}, true},
		{"negative", map[string]int{"atk": -1}, false},
		{"unknown stat key", map[string]int{"luck": 4}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := statPointsValid(tc.sp); got != tc.want {
				t.Errorf("statPointsValid(%v) = %v, want %v", tc.sp, got, tc.want)
			}
		})
	}
}

// Champions forbids two members of the same species and two members holding
// the same item. Neither rule exists in Scarlet/Violet, so neither was in the
// original builder.
func TestValidateMembersTeamRules(t *testing.T) {
	member := func(slot, pokemonID int, item *string) TeamMemberPayload {
		return TeamMemberPayload{
			Slot: slot, PokemonID: pokemonID, Nature: "jolly",
			AbilitySlug: "rough-skin", ItemSlug: item, Level: 50,
			StatPoints: map[string]int{}, Moves: []string{},
		}
	}
	band, orb := "choice-band", "life-orb"

	cases := []struct {
		name    string
		members []TeamMemberPayload
		wantErr bool
	}{
		{"distinct species and items", []TeamMemberPayload{
			member(1, 445, &band), member(2, 892, &orb)}, false},
		{"duplicate species", []TeamMemberPayload{
			member(1, 445, &band), member(2, 445, &orb)}, true},
		{"duplicate item", []TeamMemberPayload{
			member(1, 445, &band), member(2, 892, &band)}, true},
		{"two members holding nothing is fine", []TeamMemberPayload{
			member(1, 445, nil), member(2, 892, nil)}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			msg := validateMembers(tc.members)
			if (msg != "") != tc.wantErr {
				t.Errorf("validateMembers = %q, wantErr %v", msg, tc.wantErr)
			}
		})
	}
}
