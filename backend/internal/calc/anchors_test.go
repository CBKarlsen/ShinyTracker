package calc

import (
	"encoding/json"
	"os"
	"testing"
)

// oddsAnchor mirrors one entry of shared/odds_anchors.json — the language-neutral
// fixture also meant to back a future TS test and a future Swift test (see
// docs/audit/ODDS_DOMAIN_REVIEW.md finding 8). Keep this struct in sync with the
// JSON shape; it is the shared contract, not a Go-only convenience type.
type oddsAnchor struct {
	Name       string         `json:"name"`
	Formula    string         `json:"formula"`
	Params     map[string]any `json:"params"`
	BaseOdds   int            `json:"base_odds"`
	BaseRolls  int            `json:"base_rolls"`
	CharmRolls int            `json:"charm_rolls"`
	HasCharm   bool           `json:"has_charm"`
	Expected   int            `json:"expected"`
	Tolerance  int            `json:"tolerance"`
}

type oddsAnchorFile struct {
	Anchors []oddsAnchor `json:"anchors"`
}

// TestOddsAnchors asserts EffectiveOdds against shared/odds_anchors.json, the
// single source of truth shared across the Go, TS, and (future) Swift odds
// engines. Fails on any formula drift — do not delete on a refactor, update the
// shared fixture instead.
func TestOddsAnchors(t *testing.T) {
	data, err := os.ReadFile("../../../shared/odds_anchors.json")
	if err != nil {
		t.Fatalf("failed to read shared/odds_anchors.json: %v", err)
	}
	var file oddsAnchorFile
	if err := json.Unmarshal(data, &file); err != nil {
		t.Fatalf("failed to parse shared/odds_anchors.json: %v", err)
	}
	if len(file.Anchors) == 0 {
		t.Fatal("shared/odds_anchors.json contains no anchors")
	}

	for _, a := range file.Anchors {
		a := a
		t.Run(a.Name, func(t *testing.T) {
			base := OddsConfig{BaseOdds: a.BaseOdds, BaseRolls: a.BaseRolls, CharmRolls: a.CharmRolls}
			got := EffectiveOdds(a.Formula, a.Params, base, a.HasCharm)
			diff := got - a.Expected
			if diff < 0 {
				diff = -diff
			}
			if diff > a.Tolerance {
				t.Errorf("EffectiveOdds(%q, %v, charm=%v) = %d, want %d (+/- %d)",
					a.Formula, a.Params, a.HasCharm, got, a.Expected, a.Tolerance)
			}
		})
	}
}
