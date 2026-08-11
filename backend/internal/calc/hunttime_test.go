package calc

import (
	"testing"
	"time"
)

func TestDecideTotalTime(t *testing.T) {
	cases := []struct {
		name        string
		stored      int
		latched     bool
		submitted   *int
		elapsed     time.Duration
		wantTotal   int
		wantLatched bool
		wantErr     error
	}{
		{
			name:        "absent+unlatched derives from elapsed",
			stored:      100,
			latched:     false,
			submitted:   nil,
			elapsed:     30 * time.Second,
			wantTotal:   130,
			wantLatched: false,
		},
		{
			name:        "absent+unlatched with gap over threshold adds nothing",
			stored:      100,
			latched:     false,
			submitted:   nil,
			elapsed:     3 * time.Hour,
			wantTotal:   100,
			wantLatched: false,
		},
		{
			name:        "absent+latched leaves stored untouched",
			stored:      500,
			latched:     true,
			submitted:   nil,
			elapsed:     30 * time.Second,
			wantTotal:   500,
			wantLatched: true,
		},
		{
			name:        "present stores submitted and sets the latch",
			stored:      100,
			latched:     false,
			submitted:   intPtr(3600),
			elapsed:     30 * time.Second,
			wantTotal:   3600,
			wantLatched: true,
		},
		{
			name:        "present but lower than stored is clamped to stored",
			stored:      3600,
			latched:     true,
			submitted:   intPtr(1000),
			elapsed:     30 * time.Second,
			wantTotal:   3600,
			wantLatched: true,
		},
		{
			name:      "present and negative is rejected",
			stored:    100,
			latched:   false,
			submitted: intPtr(-1),
			elapsed:   30 * time.Second,
			wantErr:   ErrNegativeTotalTime,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			gotTotal, gotLatched, err := DecideTotalTime(c.stored, c.latched, c.submitted, c.elapsed)
			if c.wantErr != nil {
				if err != c.wantErr {
					t.Fatalf("DecideTotalTime err = %v, want %v", err, c.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("DecideTotalTime unexpected err = %v", err)
			}
			if gotTotal != c.wantTotal {
				t.Errorf("DecideTotalTime total = %d, want %d", gotTotal, c.wantTotal)
			}
			if gotLatched != c.wantLatched {
				t.Errorf("DecideTotalTime latched = %v, want %v", gotLatched, c.wantLatched)
			}
		})
	}
}

func intPtr(v int) *int { return &v }
