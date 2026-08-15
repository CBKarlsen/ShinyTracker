import type React from "react";
import { useCallback, useEffect, useRef, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { HeroHunt } from "../features/dashboard/HeroHunt";
import { HuntRow } from "../features/dashboard/HuntRow";
import { PhaseModal } from "../features/dashboard/PhaseModal";
import type { Hunt } from "../types/models";
import { authedFetch, SessionExpiredError } from "../utils/authedFetch";
import { isStreakMethod } from "../utils/odds";
import { EmptyState } from "./ui/EmptyState";
import { ErrorBanner } from "./ui/ErrorBanner";
import { IcPlus, SparkSm } from "./ui/icons";
import { Stat } from "./ui/Stat";
import { UndoToast } from "./ui/UndoToast";

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

// Trailing window: taps within this many ms of each other are one mistake.
const BURST_COALESCE_MS = 2500;
// How long an undo toast stays actionable before it silently expires.
const UNDO_TOAST_MS = 6000;
// Direct-entry upper bound — generous but not unbounded (guards against a
// fat-fingered extra digit going straight to the server). Mirrored in
// HeroHunt.tsx, which validates the input before it ever reaches commitCount.
const MAX_ENCOUNTER_COUNT = 999_999;

function fmtHM(s: number) {
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

// ── Dashboard ─────────────────────────────────────────────────────────────────

interface Props {
	onNewHunt: () => void;
	onHuntCountChange: (n: number) => void;
	refreshKey?: number;
}

const Dashboard: React.FC<Props> = ({
	onNewHunt,
	onHuntCountChange,
	refreshKey,
}) => {
	const { token, logout } = useAuth();
	const [hunts, setHunts] = useState<Hunt[]>([]);
	const [loading, setLoading] = useState(true);
	const [localCounts, setLocalCounts] = useState<Record<string, number>>({});
	const committedRef = useRef<Record<string, number>>({});
	const committedChainRef = useRef<Record<string, number>>({});
	const localCountsRef = useRef<Record<string, number>>({});
	const [localChains, setLocalChains] = useState<Record<string, number>>({});
	const localChainsRef = useRef<Record<string, number>>({});
	const timers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});
	const [pinnedId, setPinnedId] = useState<string | null>(null);
	const [phaseHunt, setPhaseHunt] = useState<Hunt | null>(null);
	const [errorMsg, setErrorMsg] = useState<string | null>(null);

	// Miscount undo: the count/chain a tap burst started from, keyed by hunt
	// id, plus the trailing-window timer that "seals" the burst into one undo
	// entry once taps stop for BURST_COALESCE_MS.
	const burstAnchor = useRef<Record<string, { count: number; chain: number }>>(
		{},
	);
	const burstTimers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

	// One undo entry can be showing at a time (single toast slot), but a
	// second hunt's action must not silently destroy a still-fresh entry from
	// a first hunt — queue instead. A hunt's OWN new action still supersedes
	// its own pending entry (that's deliberate: e.g. burst -> undo -> tap
	// again shouldn't leave a dangling stale undo for the same hunt).
	const [undoQueue, setUndoQueue] = useState<
		Array<{ huntId: string; message: string; revert: () => void }>
	>([]);
	const undoToast = undoQueue[0] ?? null;
	const undoDismissTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

	// Per-hunt monotonic sequence number, captured when a PATCH is issued.
	// Concurrent PATCHes for the same hunt (e.g. a debounced flush still in
	// flight when an undo fires its own revert PATCH) can resolve out of
	// order; only the response for the LATEST issued request is allowed to
	// write committedRef/committedChainRef/setHunts, so an earlier response
	// landing later can't silently overwrite a newer, correct state.
	const seqRef = useRef<Record<string, number>>({});
	const nextSeq = useCallback((id: string) => {
		const n = (seqRef.current[id] ?? 0) + 1;
		seqRef.current[id] = n;
		return n;
	}, []);
	const isLatestSeq = useCallback(
		(id: string, seq: number) => seqRef.current[id] === seq,
		[],
	);

	const handleSessionExpired = useCallback(() => {
		logout();
		setErrorMsg("Your session expired — please sign in again.");
	}, [logout]);

	// Every write path below (heartbeat, debounced flush, undo revert,
	// break-chain + its undo, phase reset) PATCHes the same hunt with an
	// absolute encounter_count. The backend used to clamp a submitted count to
	// max(stored, submitted); now it stores exactly what's submitted. So if two
	// of these PATCHes are ever in flight for one hunt and the network
	// reorders the responses, the older (lower) request can land LAST on the
	// server and silently erase encounters — seqRef only stops a stale
	// *response* from writing local state, it doesn't stop the write itself.
	// Chaining every PATCH for a hunt behind whatever is already in flight for
	// THAT hunt (and only that hunt — other hunts stay concurrent) makes that
	// server-side reordering impossible.
	const patchChains = useRef<Record<string, Promise<unknown>>>({});
	const patchHunt = useCallback(
		(id: string, body: object): Promise<Response> => {
			const prior = patchChains.current[id] ?? Promise.resolve();
			// A prior failure must not wedge this hunt's queue forever — swallow it
			// before chaining on; the caller still observes ITS OWN request's
			// success/failure via the returned promise below.
			const run = prior
				.catch(() => {})
				.then(() =>
					authedFetch(
						`${API_BASE}/api/hunts/${id}`,
						token,
						{
							method: "PATCH",
							headers: { "Content-Type": "application/json" },
							body: JSON.stringify(body),
						},
						handleSessionExpired,
					),
				);
			patchChains.current[id] = run.catch(() => {});
			return run;
		},
		[token, handleSessionExpired],
	);

	// For streak hunts, build the hunt_parameters payload carrying the live
	// chain so PATCHes advance/reset chain_length. Returns undefined for
	// non-streak hunts (their hunt_parameters must be left untouched — the
	// backend preserves existing params when the field is omitted).
	const streakParams = useCallback(
		(hunt: Hunt, chain: number): Record<string, any> | undefined => {
			if (!isStreakMethod(hunt.formula_type)) return undefined;
			const stored = (hunt.hunt_parameters as Record<string, any>) || {};
			return { ...stored, chain_length: Math.max(0, chain) };
		},
		[],
	);

	// Dismisses whichever entry is currently showing (front of queue).
	const dismissUndo = useCallback(() => {
		setUndoQueue((prev) => prev.slice(1));
	}, []);

	// Clears `huntId`'s entry wherever it sits in the queue — completing/
	// phasing one hunt shouldn't dismiss another hunt's still-valid undo.
	const dismissUndoFor = useCallback((huntId: string) => {
		setUndoQueue((prev) => prev.filter((e) => e.huntId !== huntId));
	}, []);

	// A hunt's new action replaces ITS OWN queued/showing entry (deliberate —
	// see the undoQueue comment above) but is appended behind any other
	// hunt's still-fresh entry rather than clobbering it.
	const pushUndo = useCallback(
		(huntId: string, message: string, revert: () => void) => {
			setUndoQueue((prev) => [
				...prev.filter((e) => e.huntId !== huntId),
				{ huntId, message, revert },
			]);
		},
		[],
	);

	// (Re)starts the UNDO_TOAST_MS timer whenever the front-of-queue entry
	// changes, and advances the queue when it expires unactioned.
	// biome-ignore lint/correctness/useExhaustiveDependencies: intentionally keyed on the head entry's identity (huntId+message), not the whole queue/undoToast object — appending behind the head shouldn't reset its countdown
	useEffect(() => {
		if (undoDismissTimer.current) {
			clearTimeout(undoDismissTimer.current);
			undoDismissTimer.current = null;
		}
		if (!undoToast) return;
		undoDismissTimer.current = setTimeout(() => {
			setUndoQueue((prev) => prev.slice(1));
		}, UNDO_TOAST_MS);
		return () => {
			if (undoDismissTimer.current) {
				clearTimeout(undoDismissTimer.current);
				undoDismissTimer.current = null;
			}
		};
	}, [undoToast?.huntId, undoToast?.message]);

	const fetchHunts = async () => {
		try {
			const res = await authedFetch(
				`${API_BASE}/api/hunts`,
				token,
				{},
				handleSessionExpired,
			);
			if (res.ok) {
				const data: Hunt[] = (await res.json()) || [];
				const active = data.filter((h) => h.status === "active");
				setHunts(active);
				const initial: Record<string, number> = {};
				const initialChains: Record<string, number> = {};
				for (const h of active) {
					initial[h.id] = h.encounter_count;
					// Seed the chain from stored chain_length, falling back to the
					// encounter count for legacy hunts (matches the odds fallback).
					const stored = (h.hunt_parameters as Record<string, any>) || {};
					initialChains[h.id] =
						typeof stored.chain_length === "number"
							? stored.chain_length
							: h.encounter_count;
				}
				setLocalCounts(initial);
				setLocalChains(initialChains);
				committedRef.current = { ...initial };
				localCountsRef.current = { ...initial };
				localChainsRef.current = { ...initialChains };
				committedChainRef.current = { ...initialChains };
				onHuntCountChange(active.length);
			} else {
				// A failed load must not look like a genuinely empty "no hunts yet"
				// state — surface it so the user knows their hunts didn't vanish.
				setErrorMsg("Couldn't load your hunts — the server returned an error.");
			}
		} catch (err) {
			if (err instanceof SessionExpiredError) return;
			console.error(err);
			setErrorMsg(
				"Couldn't load your hunts — check your connection and try again.",
			);
		} finally {
			setLoading(false);
		}
	};

	// biome-ignore lint/correctness/useExhaustiveDependencies: fetchHunts is defined inline and recreated each render; the refetch is driven intentionally by token + refreshKey
	useEffect(() => {
		fetchHunts();
	}, [token, refreshKey]);

	// Heartbeat: flush current encounter counts every 60s so total_time_seconds
	// stays accurate and counts survive a refresh even between +1 clicks.
	useEffect(() => {
		const id = setInterval(async () => {
			const active = Object.entries(localCounts);
			if (active.length === 0) return;
			await Promise.allSettled(
				active.map(([huntId, count]) => {
					const hunt = hunts.find((h) => h.id === huntId);
					if (!hunt) return Promise.resolve();
					const chainSent = localChainsRef.current[huntId] ?? count;
					const params = streakParams(hunt, chainSent);
					const seq = nextSeq(huntId);
					return patchHunt(huntId, {
						encounter_count: count,
						status: hunt.status,
						...(params ? { hunt_parameters: params } : {}),
					})
						.then((res) => {
							if (res.ok && isLatestSeq(huntId, seq)) {
								committedRef.current[huntId] = count;
								committedChainRef.current[huntId] = chainSent;
							}
						})
						.catch((err) => {
							if (err instanceof SessionExpiredError) return;
							console.error(err);
						});
				}),
			);
		}, 60_000);
		return () => clearInterval(id);
	}, [localCounts, hunts, streakParams, nextSeq, isLatestSeq, patchHunt]);

	// Keep localCountsRef in sync so the debounce timer always reads the latest count.
	useEffect(() => {
		localCountsRef.current = localCounts;
	}, [localCounts]);
	useEffect(() => {
		localChainsRef.current = localChains;
	}, [localChains]);

	// PATCHes whatever is currently in localCounts/localChains for `id`. Same
	// optimistic-update body used by every write path below (tap, undo revert,
	// direct entry, break-chain) so they all roll back on API error the same way.
	const flush = useCallback(
		async (id: string) => {
			const count = localCountsRef.current[id] ?? 0;
			const chain = localChainsRef.current[id] ?? 0;
			const hunt = hunts.find((h) => h.id === id);
			const params = hunt ? streakParams(hunt, chain) : undefined;
			// Captured at issue time: if a newer PATCH for this hunt is issued (by
			// this or any other write path) before this one resolves, this
			// response is stale and must not touch committedRef/setHunts.
			const seq = nextSeq(id);
			try {
				const res = await patchHunt(id, {
					encounter_count: count,
					status: "active",
					...(params ? { hunt_parameters: params } : {}),
				});
				if (!isLatestSeq(id, seq)) return;
				if (res.ok) {
					committedRef.current[id] = count;
					committedChainRef.current[id] = chain;
					setHunts((prev) =>
						prev.map((h) =>
							h.id === id
								? {
										...h,
										encounter_count: count,
										...(params ? { hunt_parameters: params } : {}),
									}
								: h,
						),
					);
				} else {
					setLocalCounts((prev) => {
						const reverted = { ...prev, [id]: committedRef.current[id] ?? 0 };
						localCountsRef.current = reverted;
						return reverted;
					});
					setLocalChains((prev) => {
						const reverted = {
							...prev,
							[id]: committedChainRef.current[id] ?? 0,
						};
						localChainsRef.current = reverted;
						return reverted;
					});
					dismissUndoFor(id);
					setErrorMsg("Sync failed — clicks weren't saved.");
				}
			} catch (err) {
				if (err instanceof SessionExpiredError) return;
				if (!isLatestSeq(id, seq)) return;
				setLocalCounts((prev) => {
					const reverted = { ...prev, [id]: committedRef.current[id] ?? 0 };
					localCountsRef.current = reverted;
					return reverted;
				});
				setLocalChains((prev) => {
					const reverted = {
						...prev,
						[id]: committedChainRef.current[id] ?? 0,
					};
					localChainsRef.current = reverted;
					return reverted;
				});
				dismissUndoFor(id);
				setErrorMsg("Sync failed — clicks weren't saved.");
			}
		},
		[hunts, streakParams, dismissUndoFor, nextSeq, isLatestSeq, patchHunt],
	);

	// (Re)start the 1500ms debounce that flushes the current count, or flush
	// right away for a deliberate one-shot edit (undo revert, direct entry).
	const scheduleFlush = useCallback(
		(id: string, immediate = false) => {
			if (timers.current[id]) {
				clearTimeout(timers.current[id]);
				delete timers.current[id];
			}
			if (immediate) {
				flush(id);
				return;
			}
			timers.current[id] = setTimeout(() => flush(id), 1500);
		},
		[flush],
	);

	// Reverts a sealed burst back to its anchor {count, chain}. Builds the
	// PATCH body directly from the captured anchor values instead of routing
	// through flush(), which reads localCountsRef/localChainsRef: this fires
	// two setState calls (count, then chain) in the same tick, and React only
	// runs the SECOND one's updater eagerly if nothing else is pending — so a
	// synchronous flush() right after could read a stale, not-yet-reverted
	// chain out of the ref and PATCH it to the server. Same direct-PATCH
	// pattern as handleBreakChain's own two-field (count+chain) revert below.
	const revertBurst = useCallback(
		async (id: string, anchor: { count: number; chain: number }) => {
			if (timers.current[id]) {
				clearTimeout(timers.current[id]);
				delete timers.current[id];
			}
			setLocalCounts((prev) => {
				const next = { ...prev, [id]: anchor.count };
				localCountsRef.current = next;
				return next;
			});
			setLocalChains((prev) => {
				const next = { ...prev, [id]: anchor.chain };
				localChainsRef.current = next;
				return next;
			});
			const hunt = hunts.find((h) => h.id === id);
			const params = hunt ? streakParams(hunt, anchor.chain) : undefined;
			const seq = nextSeq(id);
			try {
				const res = await patchHunt(id, {
					encounter_count: anchor.count,
					status: "active",
					...(params ? { hunt_parameters: params } : {}),
				});
				if (!isLatestSeq(id, seq)) return;
				if (res.ok) {
					committedRef.current[id] = anchor.count;
					committedChainRef.current[id] = anchor.chain;
					setHunts((prev) =>
						prev.map((h) =>
							h.id === id
								? {
										...h,
										encounter_count: anchor.count,
										...(params ? { hunt_parameters: params } : {}),
									}
								: h,
						),
					);
				} else {
					setErrorMsg("Undo failed — count wasn't restored.");
				}
			} catch (err) {
				if (err instanceof SessionExpiredError) return;
				if (!isLatestSeq(id, seq)) return;
				setErrorMsg("Undo failed — count wasn't restored.");
			}
		},
		[hunts, streakParams, nextSeq, isLatestSeq, patchHunt],
	);

	// Seals a tap burst into a single undo entry once BURST_COALESCE_MS has
	// passed with no further taps on this hunt.
	const sealBurst = useCallback(
		(id: string) => {
			const anchor = burstAnchor.current[id];
			delete burstAnchor.current[id];
			delete burstTimers.current[id];
			if (!anchor) return;
			const finalCount = localCountsRef.current[id] ?? 0;
			if (finalCount === anchor.count) return;
			const delta = finalCount - anchor.count;
			pushUndo(
				id,
				`+${fmtNum(delta)} encounter${delta === 1 ? "" : "s"} — undo?`,
				() => {
					revertBurst(id, anchor);
				},
			);
		},
		[pushUndo, revertBurst],
	);

	const increment = useCallback(
		(id: string) => {
			// First tap of a burst: remember where it started so a trailing-window
			// undo can revert the whole mistake, not just the last tap.
			if (!(id in burstAnchor.current)) {
				burstAnchor.current[id] = {
					count: localCountsRef.current[id] ?? 0,
					chain: localChainsRef.current[id] ?? 0,
				};
			}
			setLocalCounts((prev) => {
				const next = { ...prev, [id]: (prev[id] ?? 0) + 1 };
				localCountsRef.current = next;
				return next;
			});
			setLocalChains((prev) => {
				const next = { ...prev, [id]: (prev[id] ?? 0) + 1 };
				localChainsRef.current = next;
				return next;
			});
			scheduleFlush(id);

			if (burstTimers.current[id]) clearTimeout(burstTimers.current[id]);
			burstTimers.current[id] = setTimeout(
				() => sealBurst(id),
				BURST_COALESCE_MS,
			);
		},
		[scheduleFlush, sealBurst],
	);

	// Direct count entry (tap the number, type a value). Validated by the
	// input itself; this is a defensive second guard plus the commit.
	const commitCount = useCallback(
		(id: string, count: number) => {
			const prevCount = localCountsRef.current[id] ?? 0;
			if (!Number.isInteger(count) || count < 0 || count > MAX_ENCOUNTER_COUNT)
				return;
			if (count === prevCount) return;

			// A manual edit supersedes any tap burst in flight so a later undo
			// can't fire against a now-stale pre-burst anchor.
			if (burstTimers.current[id]) {
				clearTimeout(burstTimers.current[id]);
				delete burstTimers.current[id];
			}
			delete burstAnchor.current[id];

			setLocalCounts((prev) => {
				const next = { ...prev, [id]: count };
				localCountsRef.current = next;
				return next;
			});
			scheduleFlush(id, true);

			pushUndo(
				id,
				`Count set to ${fmtNum(count)} (was ${fmtNum(prevCount)}) — undo?`,
				() => {
					setLocalCounts((prev) => {
						const next = { ...prev, [id]: prevCount };
						localCountsRef.current = next;
						return next;
					});
					scheduleFlush(id, true);
				},
			);
		},
		[scheduleFlush, pushUndo],
	);

	// Drop any in-flight tap burst for `id` — used before an action that makes
	// the burst's undo anchor meaningless (hunt completed / phase logged).
	const clearBurst = (id: string) => {
		if (burstTimers.current[id]) {
			clearTimeout(burstTimers.current[id]);
			delete burstTimers.current[id];
		}
		delete burstAnchor.current[id];
	};

	// SPACE key → increment primary hunt
	useEffect(() => {
		const onKey = (e: KeyboardEvent) => {
			if (
				e.code === "Space" &&
				(e.target as HTMLElement).tagName !== "INPUT" &&
				(e.target as HTMLElement).tagName !== "TEXTAREA"
			) {
				e.preventDefault();
				const primary = hunts.find((h) => h.id === pinnedId) || hunts[0];
				if (primary) increment(primary.id);
			}
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [hunts, pinnedId, increment]);

	const handleIncrement = (id: string) => {
		increment(id);
	};

	const handleComplete = async (id: string) => {
		if (timers.current[id]) {
			clearTimeout(timers.current[id]);
			delete timers.current[id];
		}
		clearBurst(id);
		dismissUndoFor(id);
		const currentCount = localCounts[id] ?? 0;
		try {
			const res = await patchHunt(id, {
				encounter_count: currentCount,
				status: "completed",
			});
			if (res.ok) {
				setHunts((prev) => prev.filter((h) => h.id !== id));
				onHuntCountChange(hunts.length - 1);
				if (pinnedId === id) setPinnedId(null);
			}
		} catch (err) {
			if (err instanceof SessionExpiredError) return;
			console.error(err);
		}
	};

	const handlePin = (id: string) => {
		setPinnedId(id);
		window.scrollTo({ top: 0, behavior: "smooth" });
	};

	const handleBreakChain = async (id: string) => {
		const hunt = hunts.find((h) => h.id === id);
		if (!hunt || !isStreakMethod(hunt.formula_type)) return;
		if (timers.current[id]) {
			clearTimeout(timers.current[id]);
			delete timers.current[id];
		}
		// A pending tap burst's undo anchor captured chain BEFORE this break —
		// if left alone, its trailing timer fires after the break, clobbers
		// this action's undo toast, and its revert PATCHes the pre-break chain
		// back to the server, resurrecting the chain the user just reset.
		clearBurst(id);
		const count = localCountsRef.current[id] ?? hunt.encounter_count;
		const params = streakParams(hunt, 0) as Record<string, any>; // streak-guarded above, never undefined
		const prevChain = localChainsRef.current[id] ?? 0;
		setLocalChains((prev) => {
			const next = { ...prev, [id]: 0 };
			localChainsRef.current = next;
			return next;
		});
		const seq = nextSeq(id);
		try {
			const res = await patchHunt(id, {
				encounter_count: count,
				status: "active",
				hunt_parameters: params,
			});
			if (!isLatestSeq(id, seq)) return;
			if (res.ok) {
				setHunts((prev) =>
					prev.map((h) =>
						h.id === id ? { ...h, hunt_parameters: params } : h,
					),
				);
				committedChainRef.current[id] = 0;
				// Frequent, recoverable destructive action — undo toast instead of an
				// upfront confirm dialog (unlike "Found it!", which stays confirmed).
				pushUndo(
					id,
					`Chain reset to 0 (was ${fmtNum(prevChain)}) — undo?`,
					async () => {
						const revertParams = streakParams(hunt, prevChain) as Record<
							string,
							any
						>;
						setLocalChains((prev) => {
							const next = { ...prev, [id]: prevChain };
							localChainsRef.current = next;
							return next;
						});
						const undoSeq = nextSeq(id);
						try {
							const res2 = await patchHunt(id, {
								encounter_count: localCountsRef.current[id] ?? count,
								status: "active",
								hunt_parameters: revertParams,
							});
							if (!isLatestSeq(id, undoSeq)) return;
							if (res2.ok) {
								setHunts((prev) =>
									prev.map((h) =>
										h.id === id ? { ...h, hunt_parameters: revertParams } : h,
									),
								);
								committedChainRef.current[id] = prevChain;
							} else {
								setErrorMsg("Undo failed — chain wasn't restored.");
							}
						} catch (err) {
							if (err instanceof SessionExpiredError) return;
							if (!isLatestSeq(id, undoSeq)) return;
							setErrorMsg("Undo failed — chain wasn't restored.");
						}
					},
				);
			} else {
				setLocalChains((prev) => {
					const restored = { ...prev, [id]: prevChain };
					localChainsRef.current = restored;
					return restored;
				});
				setErrorMsg("Break failed — chain wasn't reset.");
			}
		} catch (err) {
			if (err instanceof SessionExpiredError) return;
			if (!isLatestSeq(id, seq)) return;
			setLocalChains((prev) => {
				const restored = { ...prev, [id]: prevChain };
				localChainsRef.current = restored;
				return restored;
			});
			setErrorMsg("Break failed — chain wasn't reset.");
		}
	};

	const handlePhaseSuccess = (updated: Hunt) => {
		// Cancel any pending increment flush so a stale timer can't PATCH the
		// pre-phase count over the freshly-reset phase (mirrors handleComplete).
		if (timers.current[updated.id]) {
			clearTimeout(timers.current[updated.id]);
			delete timers.current[updated.id];
		}
		clearBurst(updated.id);
		dismissUndoFor(updated.id);
		setHunts((prev) => prev.map((h) => (h.id === updated.id ? updated : h)));
		setLocalCounts((prev) => ({ ...prev, [updated.id]: 0 }));
		committedRef.current[updated.id] = 0;
		localCountsRef.current[updated.id] = 0;
		setLocalChains((prev) => ({ ...prev, [updated.id]: 0 }));
		localChainsRef.current[updated.id] = 0;
		committedChainRef.current[updated.id] = 0;
		// LogPhase resets encounter_count server-side but leaves hunt_parameters
		// untouched; persist chain_length: 0 for streak hunts so a reload doesn't
		// restore the pre-phase chain.
		if (isStreakMethod(updated.formula_type)) {
			const stored = (updated.hunt_parameters as Record<string, any>) || {};
			patchHunt(updated.id, {
				encounter_count: 0,
				status: "active",
				hunt_parameters: { ...stored, chain_length: 0 },
			}).catch((err) => {
				if (err instanceof SessionExpiredError) return;
				console.error(err);
			});
		}
		setPhaseHunt(null);
	};

	if (loading) {
		return (
			<div
				className="page"
				style={{
					color: "var(--ink-3)",
					fontFamily: "var(--font-mono)",
					fontSize: 12,
				}}
			>
				Loading hunts…
			</div>
		);
	}

	if (hunts.length === 0) {
		return (
			<div className="page">
				<div className="page-head">
					<div>
						<div className="sub">Workspace · Dashboard</div>
						<h1>No active hunts</h1>
					</div>
					<div className="ctas">
						<button className="btn gold" onClick={onNewHunt}>
							<IcPlus /> Start hunting
						</button>
					</div>
				</div>
				<ErrorBanner
					message={errorMsg || ""}
					onDismiss={() => setErrorMsg(null)}
				/>
				<EmptyState
					icon={<SparkSm size={28} />}
					title="Start your first hunt"
					description="Pick a Pokémon, choose a method, and we'll track odds, encounters and ETA. Hit SPACE to count."
					action={
						<button className="btn gold" onClick={onNewHunt}>
							<IcPlus /> New hunt
						</button>
					}
				/>
			</div>
		);
	}

	const primary = hunts.find((h) => h.id === pinnedId) || hunts[0];
	const others = hunts.filter((h) => h.id !== primary.id);
	// Merge local counts into primary/others
	const primaryChain = localChains[primary.id] ?? primary.encounter_count;
	const primaryWithCount = {
		...primary,
		encounter_count: localCounts[primary.id] ?? primary.encounter_count,
		hunt_parameters: isStreakMethod(primary.formula_type)
			? {
					...((primary.hunt_parameters as Record<string, any>) || {}),
					chain_length: primaryChain,
				}
			: primary.hunt_parameters,
	};
	const totalEncounters = hunts.reduce(
		(s, h) => s + (localCounts[h.id] ?? h.encounter_count),
		0,
	);
	const totalTime = hunts.reduce((s, h) => s + h.total_time_seconds, 0);

	const today = new Date().toLocaleDateString("en-US", {
		weekday: "long",
		month: "long",
		day: "numeric",
	});

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · {today}</div>
					<h1>Dashboard</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						{hunts.length} active · {fmtNum(totalEncounters)} encounters ·{" "}
						{fmtHM(totalTime)} hunted
					</div>
				</div>
				<div className="ctas">
					<button className="btn ghost">Filter</button>
					<button className="btn gold" onClick={onNewHunt}>
						<IcPlus /> New hunt
					</button>
				</div>
			</div>

			<ErrorBanner
				message={errorMsg || ""}
				onDismiss={() => setErrorMsg(null)}
			/>

			{undoToast && (
				<UndoToast
					message={undoToast.message}
					onUndo={() => {
						undoToast.revert();
						dismissUndo();
					}}
					onDismiss={dismissUndo}
				/>
			)}

			<HeroHunt
				key={primary.id}
				hunt={primaryWithCount}
				onIncrement={handleIncrement}
				onComplete={handleComplete}
				onPhase={setPhaseHunt}
				onBreakChain={handleBreakChain}
				onSetCount={commitCount}
				onUpdate={(updated) => {
					const existing = hunts.find((h) => h.id === updated.id);
					// `updated.encounter_count` is a stale passenger: the params save
					// deliberately sends no count, so the server echoes whatever it had
					// stored, which can lag an in-flight tap flush by a round trip.
					// Harmless only because every display and write path treats
					// `hunts[i].encounter_count` as the fallback behind localCounts —
					// read it directly and this becomes a rollback.
					setHunts((prev) =>
						prev.map((h) => (h.id === updated.id ? { ...h, ...updated } : h)),
					);
					// If a streak hunt's params were just saved, sync the optimistic
					// chain to the saved value so the render injection doesn't override
					// it with the stale live value (e.g. Poké Radar manual chain edit).
					const params = (updated.hunt_parameters as Record<string, any>) || {};
					if (
						existing &&
						isStreakMethod(existing.formula_type) &&
						typeof params.chain_length === "number"
					) {
						const saved = params.chain_length;
						setLocalChains((prev) => {
							const next = { ...prev, [updated.id]: saved };
							localChainsRef.current = next;
							return next;
						});
						committedChainRef.current[updated.id] = saved;
					}
				}}
			/>

			<div style={{ height: 22 }} />

			<div className="stat-row">
				<Stat label="Active Hunts" value={hunts.length} accent="var(--blue)" />
				<Stat label="Total Encounters" value={fmtNum(totalEncounters)} />
				<Stat label="Total Hunted" value={fmtHM(totalTime)} />
				<Stat
					label="Avg per Hunt"
					value={
						hunts.length > 0
							? fmtNum(Math.floor(totalEncounters / hunts.length))
							: "0"
					}
				/>
			</div>

			{others.length > 0 && (
				<>
					<div style={{ height: 22 }} />
					<div className="card flush">
						<div className="card-head">
							<h3>Other active hunts</h3>
							<span className="t-label">{others.length} hunts</span>
							<div className="right">
								<span
									style={{
										fontFamily: "var(--font-mono)",
										fontSize: 10.5,
										color: "var(--ink-3)",
									}}
								>
									Click row to promote to main
								</span>
							</div>
						</div>
						<div className="hunt-list">
							{others.map((h) => (
								<HuntRow
									key={h.id}
									hunt={{
										...h,
										encounter_count: localCounts[h.id] ?? h.encounter_count,
										hunt_parameters: isStreakMethod(h.formula_type)
											? {
													...((h.hunt_parameters as Record<string, any>) || {}),
													chain_length: localChains[h.id] ?? h.encounter_count,
												}
											: h.hunt_parameters,
									}}
									onIncrement={handleIncrement}
									onComplete={handleComplete}
									onPhase={setPhaseHunt}
									onBreakChain={handleBreakChain}
									onPin={handlePin}
								/>
							))}
						</div>
					</div>
				</>
			)}

			{phaseHunt && token && (
				<PhaseModal
					hunt={phaseHunt}
					token={token}
					onClose={() => setPhaseHunt(null)}
					onSuccess={handlePhaseSuccess}
				/>
			)}
		</div>
	);
};

export default Dashboard;
