package api

import "testing"

func TestEVSpreadValid(t *testing.T) {
	cases := []struct {
		name string
		evs  map[string]int
		want bool
	}{
		{"empty is fine", map[string]int{}, true},
		{"exactly 508 total", map[string]int{"atk": 252, "spe": 252, "spd": 4}, true},
		{"509 is over the cap", map[string]int{"atk": 252, "spe": 252, "spd": 5}, false},
		{"253 in one stat", map[string]int{"atk": 253}, false},
		{"negative", map[string]int{"atk": -4}, false},
		{"unknown stat key", map[string]int{"luck": 4}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := evSpreadValid(tc.evs); got != tc.want {
				t.Errorf("evSpreadValid(%v) = %v, want %v", tc.evs, got, tc.want)
			}
		})
	}
}

func TestIVSpreadValid(t *testing.T) {
	cases := []struct {
		name string
		ivs  map[string]int
		want bool
	}{
		{"empty is fine", map[string]int{}, true},
		{"all 31", map[string]int{"hp": 31, "atk": 31, "spe": 31}, true},
		{"zero is legal", map[string]int{"atk": 0}, true},
		{"32 is not", map[string]int{"atk": 32}, false},
		{"negative", map[string]int{"atk": -1}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := ivSpreadValid(tc.ivs); got != tc.want {
				t.Errorf("ivSpreadValid(%v) = %v, want %v", tc.ivs, got, tc.want)
			}
		})
	}
}
