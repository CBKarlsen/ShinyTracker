package api

import (
	"strings"
	"testing"
)

func TestNicknameTooLong(t *testing.T) {
	ptr := func(s string) *string { return &s }

	cases := []struct {
		name     string
		nickname *string
		want     bool
	}{
		{"absent is never too long", nil, false},
		{"empty is fine", ptr(""), false},
		{"at the cap is fine", ptr(strings.Repeat("a", maxNicknameLength)), false},
		{"one over the cap is rejected", ptr(strings.Repeat("a", maxNicknameLength+1)), true},

		// The reason this is counted in runes and not bytes. Each of these is one
		// character to the user and three bytes to len(), so a byte-counted cap would
		// reject a name a third of the allowed length.
		{
			"a full-length multi-byte name is allowed",
			ptr(strings.Repeat("あ", maxNicknameLength)),
			false,
		},
		{
			"a multi-byte name over the cap is still rejected",
			ptr(strings.Repeat("あ", maxNicknameLength+1)),
			true,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := nicknameTooLong(c.nickname); got != c.want {
				t.Errorf("nicknameTooLong(%v) = %v, want %v", c.nickname, got, c.want)
			}
		})
	}
}
