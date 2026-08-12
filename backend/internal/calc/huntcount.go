package calc

// DecideEncounterCount resolves a submitted encounter count against the stored
// one, per D1 (docs/handoff/DECISIONS.md): the count is a monotonic counter.
// "Never overwrite a higher server value with a lower local one without an
// explicit user decision… Losing a long hunt is the one unforgivable failure
// in this app." A sync, a replayed offline burst, or a second device counting
// the same hunt can therefore only ever raise it.
//
//   - stored: the hunt's current encounter_count.
//   - submitted: the request's encounter_count. Always present (unlike
//     DecideTotalTime's submitted, there is no pre-D1 caller that omits this).
//   - allowDecrease: the "−" control's explicit permission to lower the count.
//     Only that control ever sets it — never sync, never replay.
//
// allowDecrease true: store submitted as-is. This is the explicit user
// decision D1 requires, so a lower value is honoured and a higher one is not
// held back either — the control simply sets the count to what the user chose.
//
// allowDecrease false: store max(stored, submitted). A bare SQL GREATEST would
// do the same, but only from inside the UPDATE where it can't be unit-tested —
// the same reason UpdateHuntHandler calls out to DecideTotalTime rather than
// deciding total_time_seconds in the query.
func DecideEncounterCount(stored, submitted int, allowDecrease bool) int {
	if allowDecrease {
		return submitted
	}
	if submitted > stored {
		return submitted
	}
	return stored
}
