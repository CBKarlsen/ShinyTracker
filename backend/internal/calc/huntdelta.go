package calc

// ApplyEncounterDelta moves a stored encounter count by a relative amount.
//
// Deltas exist because an offline client cannot know the current count. An
// absolute write from a stale client overwrites whatever the server holds,
// which is the failure D1 calls unforgivable and which the iOS client spent
// five fix passes defending against; a relative one cannot, whatever the
// client believes.
//
// The clamp is the one guard a delta still needs: relative writes cannot be
// stale, but they can be wrong, and encounter_count has no CHECK constraint.
func ApplyEncounterDelta(stored, delta int) int {
	next := stored + delta
	if next < 0 {
		return 0
	}
	return next
}
