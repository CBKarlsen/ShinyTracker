package calc

import "testing"

// Parity targets computed directly from frontend/src/utils/odds.ts.
func TestEffectiveOddsParity(t *testing.T) {
	base := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2}
	cases := []struct {
		name    string
		formula string
		params  map[string]any
		charm   bool
		want    int
	}{
		{"static no charm", "static", nil, false, 4096},
		{"static charm", "static", nil, true, 1365},
		{"outbreak d60+pw3+charm", "outbreak_defeats_sv", map[string]any{"defeated_count": 60, "sparkling_power": 3}, true, 512},
		{"outbreak d30 no charm", "outbreak_defeats_sv", map[string]any{"defeated_count": 30}, false, 2048},
		{"sandwich pw3 no charm", "sandwich_power_sv", map[string]any{"sparkling_power": 3}, false, 1024},
		{"sos chain31 no charm", "sos_chain_gen7", map[string]any{"chain_length": 31}, false, 315},
		{"sos chain10 no charm", "sos_chain_gen7", map[string]any{"chain_length": 10}, false, 4096},
		{"radar chain40", "radar_chain_gen4", map[string]any{"chain_length": 40}, false, 200},
		{"radar chain40 charm ignored", "radar_chain_gen4", map[string]any{"chain_length": 40}, true, 200},
		{"radar chain1", "radar_chain_gen4", map[string]any{"chain_length": 1}, false, 7282},
		{"radar chain0", "radar_chain_gen4", map[string]any{"chain_length": 0}, false, 8192},
		{"dynamax no charm", "dynamax_adventures_gen8", nil, false, 300},
		{"dynamax charm", "dynamax_adventures_gen8", nil, true, 100},
		{"dexnav sl200 ch100", "dexnav_gen6", map[string]any{"search_level": 200, "chain_length": 100}, false, 12},
		{"unknown falls back to static", "no_such_formula", nil, false, 4096},
		{"float64 params tolerated", "outbreak_defeats_sv", map[string]any{"defeated_count": float64(60), "sparkling_power": float64(3)}, true, 512},
		{"empty formula is static", "", nil, false, 4096},
	}
	for _, c := range cases {
		got := EffectiveOdds(c.formula, c.params, base, c.charm)
		if got != c.want {
			t.Errorf("%s: EffectiveOdds = %d, want %d", c.name, got, c.want)
		}
	}
}

// catch_combo and chain_fishing read the live count, fed via the "count" param.
func TestEffectiveOddsCountDriven(t *testing.T) {
	base := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2}
	if got := EffectiveOdds("catch_combo_lgpe", map[string]any{"count": 31}, base, false); got != 341 {
		t.Errorf("catch_combo combo31 = %d, want 341", got)
	}
	if got := EffectiveOdds("chain_fishing_gen6", map[string]any{"count": 20}, base, false); got != 99 {
		t.Errorf("chain_fishing chain20 = %d, want 99", got)
	}
}

func TestDefaultParamsDriveBestOdds(t *testing.T) {
	base := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2}
	// With default best params + charm, outbreak should reach the 1/512 stack.
	if got := EffectiveOdds("outbreak_defeats_sv", DefaultParams("outbreak_defeats_sv"), base, true); got != 512 {
		t.Errorf("outbreak default+charm = %d, want 512", got)
	}
	// Radar default should be the chain-40 plateau, 200.
	if got := EffectiveOdds("radar_chain_gen4", DefaultParams("radar_chain_gen4"), base, false); got != 200 {
		t.Errorf("radar default = %d, want 200", got)
	}
	// Static has no params.
	if dp := DefaultParams("static"); len(dp) != 0 {
		t.Errorf("static default params = %v, want empty", dp)
	}
}
