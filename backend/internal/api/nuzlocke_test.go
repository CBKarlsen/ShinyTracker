package api

import "testing"

func TestIsDupeCatch(t *testing.T) {
	cases := []struct {
		name                   string
		dupesClauseOn          bool
		status                 string
		pokemonID              int
		alreadyCaughtElsewhere []int
		want                   bool
	}{
		{"clause off never flags", false, "caught", 399, []int{399}, false},
		{"missed is never a dupe", true, "missed", 399, []int{399}, false},
		{"fainted is never a dupe", true, "fainted", 399, []int{399}, false},
		{"ran is never a dupe", true, "ran", 399, []int{399}, false},
		{"first catch of a species is not a dupe", true, "caught", 399, nil, false},
		{"caught species already caught elsewhere is a dupe", true, "caught", 399, []int{396, 399}, true},
		{"caught species not caught elsewhere is not a dupe", true, "caught", 401, []int{396, 399}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := isDupeCatch(c.dupesClauseOn, c.status, c.pokemonID, c.alreadyCaughtElsewhere)
			if got != c.want {
				t.Errorf("isDupeCatch(%v, %q, %d, %v) = %v, want %v",
					c.dupesClauseOn, c.status, c.pokemonID, c.alreadyCaughtElsewhere, got, c.want)
			}
		})
	}
}

func TestNeedsNickname(t *testing.T) {
	nonEmpty := "Sparky"
	empty := ""
	blank := "   "

	cases := []struct {
		name              string
		nicknamesRequired bool
		status            string
		nickname          *string
		want              bool
	}{
		{"not required never blocks", false, "caught", nil, false},
		{"missed never needs a nickname", true, "missed", nil, false},
		{"ran never needs a nickname", true, "ran", nil, false},
		{"caught with no nickname is blocked", true, "caught", nil, true},
		{"caught with empty nickname is blocked", true, "caught", &empty, true},
		{"caught with whitespace-only nickname is blocked", true, "caught", &blank, true},
		{"caught with a real nickname passes", true, "caught", &nonEmpty, false},
		{"fainted with no nickname is blocked", true, "fainted", nil, true},
		{"fainted with a real nickname passes", true, "fainted", &nonEmpty, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := needsNickname(c.nicknamesRequired, c.status, c.nickname)
			if got != c.want {
				t.Errorf("needsNickname(%v, %q, %v) = %v, want %v", c.nicknamesRequired, c.status, c.nickname, got, c.want)
			}
		})
	}
}
