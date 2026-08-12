package calc

// DecideEncounterCount resolves a submitted encounter count against the stored
// one.
//
// D1 (docs/handoff/DECISIONS.md): the count is a monotonic counter. "Never
// overwrite a higher server value with a lower local one without an explicit
// user decision… Losing a long hunt is the one unforgivable failure in this
// app." A sync, a replayed offline burst, or a second device counting the same
// hunt can therefore only ever raise it.
//
// allowDecrease is that explicit decision, and it travels with the request
// because the app has a "−" control and legitimate decrements exist. A bare
// GREATEST would silently break that button; only the minus control sets this,
// never sync and never replay.
func DecideEncounterCount(stored, submitted int, allowDecrease bool) int {
	if allowDecrease {
		return submitted
	}
	if submitted > stored {
		return submitted
	}
	return stored
}
