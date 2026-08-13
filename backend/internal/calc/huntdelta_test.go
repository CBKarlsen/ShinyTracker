package calc

import "testing"

func TestApplyEncounterDelta(t *testing.T) {
	cases := []struct {
		name   string
		stored int
		delta  int
		want   int
	}{
		{"an increment adds", 2847, 500, 3347},
		{"a decrement subtracts", 2847, -1, 2846},
		{"a zero delta is a no-op", 2847, 0, 2847},
		// A delta is relative, so it cannot be stale — but it can still be wrong, and the
		// column has no CHECK. Clamping here keeps a bad client from writing nonsense.
		{"the count never goes below zero", 3, -10, 0},
		{"a decrement to exactly zero is allowed", 3, -3, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := ApplyEncounterDelta(c.stored, c.delta); got != c.want {
				t.Errorf("ApplyEncounterDelta(%d, %d) = %d, want %d", c.stored, c.delta, got, c.want)
			}
		})
	}
}
