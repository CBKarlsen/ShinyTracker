package calc

import (
	"errors"
	"time"
)

// HuntTimeInactivityThreshold is the gap beyond which a server-derived
// elapsed duration is discarded rather than credited. Mirrors the historic
// UpdateHuntHandler heuristic: a PATCH gap this large almost certainly means
// the app was closed/backgrounded, not that the user hunted continuously.
const HuntTimeInactivityThreshold = 600 * time.Second

// ErrNegativeTotalTime is returned by DecideTotalTime when the client submits
// a negative total_time_seconds.
var ErrNegativeTotalTime = errors.New("total_time_seconds must be >= 0")

// DecideTotalTime picks the total_time_seconds (and client_owns_time latch)
// to store for a hunt on a PATCH, per D1 (docs/handoff/DECISIONS.md):
// elapsed time is client-authoritative once a client starts sending it.
//
//   - stored: the hunt's current total_time_seconds.
//   - latched: the hunt's current client_owns_time.
//   - submitted: the request's total_time_seconds, or nil if the caller
//     didn't send one (the pre-D1 web frontend never does).
//   - elapsed: time.Since(updated_at) at the moment of this PATCH, used only
//     for server-side derivation when submitted is nil and the hunt isn't
//     latched yet.
//
// submitted present: the client owns this hunt's time from here on. Store
// max(stored, *submitted) — time only accumulates, so a lower submitted value
// can only be a stale/out-of-order write, never a legitimate correction — and
// latch the hunt so no future PATCH derives for it again.
//
// submitted absent, latched: leave stored untouched. A client already owns
// this hunt's time; deriving from the gap here would double-count time that
// client already accounted for.
//
// submitted absent, unlatched: the pre-D1 behavior — derive from elapsed,
// discarding gaps at or beyond HuntTimeInactivityThreshold.
func DecideTotalTime(stored int, latched bool, submitted *int, elapsed time.Duration) (newTotal int, newLatched bool, err error) {
	if submitted != nil {
		if *submitted < 0 {
			return 0, false, ErrNegativeTotalTime
		}
		if *submitted > stored {
			return *submitted, true, nil
		}
		return stored, true, nil
	}
	if latched {
		return stored, true, nil
	}
	if elapsed < HuntTimeInactivityThreshold {
		return stored + int(elapsed.Seconds()), false, nil
	}
	return stored, false, nil
}
