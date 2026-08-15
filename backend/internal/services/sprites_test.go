package services

import "testing"

// The failure mode this guards is silent and total: get the rewrite wrong and
// every sprite in the Dex grid becomes a blank plate, with nothing in any log.
func TestCDNSpriteURL(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "rewrites a PokeAPI sprite URL onto jsDelivr",
			in:   "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/25.png",
			want: "https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/sprites/pokemon/25.png",
		},
		{
			name: "rewrites the shiny path the same way",
			in:   "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/25.png",
			want: "https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/sprites/pokemon/shiny/25.png",
		},
		{
			// PokeAPI returns null for some forms; the column is NOT NULL-ish by
			// convention and the clients treat "" as "fall back to the base host".
			name: "leaves an empty URL alone",
			in:   "",
			want: "",
		},
		{
			// Someone may point a species at a mirror by hand. Rewriting only the
			// known host means that survives a re-seed instead of being mangled.
			name: "leaves an unrelated host alone",
			in:   "https://example.invalid/sprites/25.png",
			want: "https://example.invalid/sprites/25.png",
		},
		{
			name: "is idempotent — a re-seed must not double-rewrite",
			in:   "https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/sprites/pokemon/25.png",
			want: "https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/sprites/pokemon/25.png",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := cdnSpriteURL(tc.in); got != tc.want {
				t.Errorf("cdnSpriteURL(%q)\n got: %q\nwant: %q", tc.in, got, tc.want)
			}
		})
	}
}
