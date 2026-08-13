package calc

import "testing"

func TestDecideEncounterCount(t *testing.T) {
	cases := []struct {
		name          string
		stored        int
		submitted     int
		allowDecrease bool
		want          int
	}{
		{"a higher count always writes", 100, 250, false, 250},
		{"an equal count writes", 100, 100, false, 100},
		// The rule D1 exists for: a stale or replayed write must never lose counted encounters.
		{"a lower count is refused without permission", 2847, 12, false, 2847},
		{"a lower count is honoured when the user asked", 2847, 2846, true, 2846},
		{"the minus button can reach zero", 1, 0, true, 0},
		{"permission does not raise a lower stored value", 5, 9, true, 9},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := DecideEncounterCount(c.stored, c.submitted, c.allowDecrease); got != c.want {
				t.Errorf("DecideEncounterCount(%d, %d, %v) = %d, want %d",
					c.stored, c.submitted, c.allowDecrease, got, c.want)
			}
		})
	}
}
