package services

import (
	"encoding/json"
	"testing"
)

// samplePokemonPayload is a trimmed, real-shaped fragment of PokeAPI's
// /pokemon/{id} response (based on Pikachu, #25) covering: stats out of the
// documented hp/attack/.../speed order (to prove parseBaseStats keys by name,
// not position), two ability slots (one hidden), and a moveset with several
// version groups per move -- one we seed (platinum), one we don't
// (black-white), and a learn method we don't model (form-change) that must
// be dropped rather than misfiled into one of our four buckets.
const samplePokemonPayload = `{
  "stats": [
    {"base_stat": 90, "stat": {"name": "speed"}},
    {"base_stat": 35, "stat": {"name": "hp"}},
    {"base_stat": 55, "stat": {"name": "attack"}},
    {"base_stat": 40, "stat": {"name": "defense"}},
    {"base_stat": 50, "stat": {"name": "special-attack"}},
    {"base_stat": 50, "stat": {"name": "special-defense"}}
  ],
  "abilities": [
    {"ability": {"name": "static", "url": "https://pokeapi.co/api/v2/ability/9/"}, "is_hidden": false, "slot": 1},
    {"ability": {"name": "lightning-rod", "url": "https://pokeapi.co/api/v2/ability/31/"}, "is_hidden": true, "slot": 3}
  ],
  "moves": [
    {
      "move": {"name": "thunderbolt", "url": "https://pokeapi.co/api/v2/move/85/"},
      "version_group_details": [
        {"level_learned_at": 26, "move_learn_method": {"name": "level-up"}, "version_group": {"name": "platinum"}},
        {"level_learned_at": 0, "move_learn_method": {"name": "machine"}, "version_group": {"name": "black-white"}}
      ]
    },
    {
      "move": {"name": "volt-tackle", "url": "https://pokeapi.co/api/v2/move/344/"},
      "version_group_details": [
        {"level_learned_at": 0, "move_learn_method": {"name": "egg"}, "version_group": {"name": "platinum"}}
      ]
    },
    {
      "move": {"name": "thunder-punch", "url": "https://pokeapi.co/api/v2/move/9/"},
      "version_group_details": [
        {"level_learned_at": 0, "move_learn_method": {"name": "tutor"}, "version_group": {"name": "scarlet-violet"}},
        {"level_learned_at": 0, "move_learn_method": {"name": "form-change"}, "version_group": {"name": "scarlet-violet"}}
      ]
    }
  ]
}`

func decodeSamplePokemon(t *testing.T) pokeAPISpeciesMoveset {
	t.Helper()
	var sm pokeAPISpeciesMoveset
	if err := json.Unmarshal([]byte(samplePokemonPayload), &sm); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return sm
}

func TestParseBaseStats(t *testing.T) {
	sm := decodeSamplePokemon(t)
	stats, ok := parseBaseStats(sm.Stats)
	if !ok {
		t.Fatal("parseBaseStats reported incomplete, want complete")
	}
	want := BaseStats{HP: 35, Attack: 55, Defense: 40, SpecialAttack: 50, SpecialDefense: 50, Speed: 90}
	if stats != want {
		t.Errorf("parseBaseStats = %+v, want %+v", stats, want)
	}
}

func TestParseBaseStatsIncomplete(t *testing.T) {
	_, ok := parseBaseStats([]pokeAPIStatEntry{{BaseStat: 35, Stat: struct {
		Name string `json:"name"`
	}{Name: "hp"}}})
	if ok {
		t.Error("parseBaseStats reported complete for a payload missing 5 of 6 stats")
	}
}

func TestParseAbilitySlots(t *testing.T) {
	sm := decodeSamplePokemon(t)
	slots := parseAbilitySlots(sm.Abilities)
	if len(slots) != 2 {
		t.Fatalf("len(slots) = %d, want 2", len(slots))
	}
	if slots[0] != (AbilitySlotRef{Slug: "static", Slot: 1, IsHidden: false}) {
		t.Errorf("slots[0] = %+v", slots[0])
	}
	if slots[1] != (AbilitySlotRef{Slug: "lightning-rod", Slot: 3, IsHidden: true}) {
		t.Errorf("slots[1] = %+v", slots[1])
	}
}

func TestNormalizeLearnMethod(t *testing.T) {
	cases := []struct {
		in      string
		wantOut string
		wantOK  bool
	}{
		{"level-up", "level-up", true},
		{"machine", "tm", true}, // PokeAPI's TM/TR/HM bucket maps to our "tm"
		{"egg", "egg", true},
		{"tutor", "tutor", true},
		{"train", "train", true}, // Champions' only learn method -- no levelling, no TMs
		{"form-change", "", false},
		{"stadium-surfing-pikachu", "", false},
	}
	for _, c := range cases {
		got, ok := normalizeLearnMethod(c.in)
		if got != c.wantOut || ok != c.wantOK {
			t.Errorf("normalizeLearnMethod(%q) = (%q, %v), want (%q, %v)", c.in, got, ok, c.wantOut, c.wantOK)
		}
	}
}

func TestParseMoveset(t *testing.T) {
	sm := decodeSamplePokemon(t)
	entries := parseMoveset(sm.Moves)

	// Expected: thunderbolt/platinum/level-up(26) survives; thunderbolt's
	// black-white/machine row is dropped (not a seeded version group);
	// volt-tackle/platinum/egg survives with a nil level; thunder-punch's
	// scarlet-violet/tutor row survives; its form-change row (unmodeled
	// method) is dropped even though scarlet-violet is a seeded game.
	if len(entries) != 3 {
		t.Fatalf("len(entries) = %d, want 3: %+v", len(entries), entries)
	}

	byMove := map[string]MoveLearnEntry{}
	for _, e := range entries {
		byMove[e.MoveSlug] = e
	}

	tb, ok := byMove["thunderbolt"]
	if !ok {
		t.Fatal("missing thunderbolt entry")
	}
	if tb.GameTitle != "Diamond/Pearl/Platinum" || tb.Method != "level-up" {
		t.Errorf("thunderbolt = %+v", tb)
	}
	if tb.Level == nil || *tb.Level != 26 {
		t.Errorf("thunderbolt.Level = %v, want 26", tb.Level)
	}

	vt, ok := byMove["volt-tackle"]
	if !ok {
		t.Fatal("missing volt-tackle entry")
	}
	if vt.Method != "egg" || vt.Level != nil {
		t.Errorf("volt-tackle = %+v, want method=egg level=nil", vt)
	}

	tp, ok := byMove["thunder-punch"]
	if !ok {
		t.Fatal("missing thunder-punch entry (its tutor row should have survived)")
	}
	if tp.GameTitle != "Scarlet/Violet" || tp.Method != "tutor" {
		t.Errorf("thunder-punch = %+v", tp)
	}
}

// sampleMovePayload is a trimmed real-shaped /move/{id} response (Thunderbolt,
// #85), covering multi-language names/effect_entries so englishName and
// englishEffect are exercised against the exact shape they'll see in
// production, not a hand-simplified one.
const sampleMovePayload = `{
  "name": "thunderbolt",
  "power": 90,
  "accuracy": 100,
  "pp": 15,
  "type": {"name": "electric"},
  "damage_class": {"name": "special"},
  "names": [
    {"name": "10まんボルト", "language": {"name": "ja"}},
    {"name": "Thunderbolt", "language": {"name": "en"}}
  ],
  "effect_entries": [
    {"short_effect": "Effet francais", "language": {"name": "fr"}},
    {"short_effect": "Has a chance to paralyze the target.", "language": {"name": "en"}}
  ]
}`

func TestPokeAPIMoveDetailParsing(t *testing.T) {
	var d pokeAPIMoveDetail
	if err := json.Unmarshal([]byte(sampleMovePayload), &d); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if d.Name != "thunderbolt" {
		t.Errorf("Name = %q, want thunderbolt", d.Name)
	}
	if d.Power == nil || *d.Power != 90 {
		t.Errorf("Power = %v, want 90", d.Power)
	}
	if d.Accuracy == nil || *d.Accuracy != 100 {
		t.Errorf("Accuracy = %v, want 100", d.Accuracy)
	}
	if d.PP != 15 {
		t.Errorf("PP = %d, want 15", d.PP)
	}
	if d.Type.Name != "electric" {
		t.Errorf("Type.Name = %q, want electric", d.Type.Name)
	}
	if d.DamageClass.Name != "special" {
		t.Errorf("DamageClass.Name = %q, want special", d.DamageClass.Name)
	}
	if got := englishName(d.Names, d.Name); got != "Thunderbolt" {
		t.Errorf("englishName = %q, want Thunderbolt", got)
	}
	if got := englishEffect(d.EffectEntries); got != "Has a chance to paralyze the target." {
		t.Errorf("englishEffect = %q, want the english short_effect", got)
	}
}

// A status move (power/accuracy both null in PokeAPI, e.g. Swords Dance) must
// decode to nil pointers, not zero -- power 0 and "no power" are different
// things for a physical/special move to accidentally collide with.
func TestPokeAPIMoveDetailNullablePowerAccuracy(t *testing.T) {
	const statusMove = `{"name": "swords-dance", "power": null, "accuracy": null, "pp": 20,
		"type": {"name": "normal"}, "damage_class": {"name": "status"}, "names": [], "effect_entries": []}`
	var d pokeAPIMoveDetail
	if err := json.Unmarshal([]byte(statusMove), &d); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if d.Power != nil {
		t.Errorf("Power = %v, want nil", d.Power)
	}
	if d.Accuracy != nil {
		t.Errorf("Accuracy = %v, want nil", d.Accuracy)
	}
	if got := englishName(d.Names, "swords-dance"); got != "swords-dance" {
		t.Errorf("englishName fallback = %q, want the slug fallback", got)
	}
	if got := englishEffect(d.EffectEntries); got != "" {
		t.Errorf("englishEffect = %q, want empty for no entries", got)
	}
}
