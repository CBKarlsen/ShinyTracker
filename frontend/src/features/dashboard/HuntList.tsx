import type { Hunt } from "../../types/models";
import { shinyCharmAvailable } from "../../utils/games";
import { getSpriteUrl } from "../../utils/pokemon";

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

function gameShort(title: string | null): string {
	if (!title) return "—";
	const map: Record<string, string> = {
		"Scarlet/Violet": "SV",
		"Sword/Shield": "SW",
		Sword: "SW",
		Shield: "SH",
		"Brilliant Diamond/Shining Pearl": "BD",
		BDSP: "BD",
		"Legends: Arceus": "LA",
		"Omega Ruby/Alpha Sapphire": "OR",
		"Omega Ruby": "OR",
		"Alpha Sapphire": "AS",
		"HeartGold/SoulSilver": "HG",
		"Let's Go Pikachu/Eevee": "LG",
		"X/Y": "XY",
		"Ultra Sun/Ultra Moon": "US",
		"Sun/Moon": "SM",
		"Black 2/White 2": "B2",
		"Black/White": "BW",
		"Diamond/Pearl": "DP",
		Platinum: "Pt",
		Crystal: "C",
		"Gold/Silver": "GS",
		"Red/Blue/Yellow": "RB",
	};
	return map[title] || title.slice(0, 2).toUpperCase();
}

function getEffectiveRolls(hunt: Hunt): number | null {
	if (hunt.base_rolls == null) return null;
	// Gate charm: only count charm rolls when the charm actually exists in this game.
	const charmActive = (hunt.has_shiny_charm ?? false) && shinyCharmAvailable(hunt.game_id);
	return hunt.base_rolls + (charmActive && hunt.charm_rolls != null ? hunt.charm_rolls : 0);
}

function getLuckLabel(pct: number): string {
	if (pct < 0.33) return "running lucky";
	if (pct < 0.67) return "about average";
	if (pct < 0.90) return "pushing your luck";
	return "overdue";
}

const IcPin = () => (
	<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round">
		<path d="M8 1.5l2.4 4.3 2.6.6-1.8 2 .4 2.6L8 9.8 4.4 11l.4-2.6L3 6.4l2.6-.6L8 1.5z" />
	</svg>
);

export function HuntList({
	hunts,
	pinnedId,
	onPin,
	onDelete,
}: {
	hunts: Hunt[];
	pinnedId: string | null;
	onPin: (id: string) => void;
	onDelete: (id: string) => void;
}) {
	if (hunts.length === 0) return null;

	return (
		<div className="table-container">
			<table>
				<thead>
					<tr>
						<th style={{ width: 40 }} />
						<th style={{ width: 220 }}>Pokemon</th>
						<th style={{ width: 100 }}>Game</th>
						<th style={{ width: 140 }}>Method</th>
						<th>Encounters</th>
						<th>Status</th>
						<th style={{ width: 60 }} />
					</tr>
				</thead>
				<tbody>
					{hunts.map((h) => {
						const isPinned = h.id === pinnedId;
						const odds = h.base_odds || 4096;
						const rolls = getEffectiveRolls(h) || 1;
						const youP = 1 - Math.pow(1 - rolls / odds, h.encounter_count);
						const spriteUrl = getSpriteUrl(h.pokemon_id, true, h.shiny_sprite_url);

						return (
							<tr key={h.id} className={isPinned ? "pinned" : ""}>
								<td>
									<button
										className={`pin-btn ${isPinned ? "active" : ""}`}
										onClick={() => onPin(h.id)}
										title={isPinned ? "Unpin hunt" : "Pin hunt to top"}
									>
										<IcPin />
									</button>
								</td>
								<td>
									<div style={{ display: "flex", alignItems: "center", gap: 10 }}>
										<img
											src={spriteUrl}
											alt=""
											style={{
												width: 32,
												height: 32,
												imageRendering: "pixelated",
											}}
										/>
										<div>
											<div style={{ fontWeight: 500, color: "var(--ink-1)", textTransform: "capitalize" }}>
												{h.pokemon_name}
											</div>
											<div style={{ fontSize: 11, color: "var(--ink-3)", marginTop: 2 }}>
												{new Date(h.created_at).toLocaleDateString()}
											</div>
										</div>
									</div>
								</td>
								<td>
									<span className="game-badge">{gameShort(h.game_title)}</span>
								</td>
								<td>
									<div style={{ fontSize: 13, color: "var(--ink-1)" }}>
										{h.custom_method_name ? h.custom_method_name : h.method_name}
									</div>
									{h.has_shiny_charm && shinyCharmAvailable(h.game_id) && (
										<div style={{ fontSize: 11, color: "var(--gold)", marginTop: 2 }}>
											+ Charm
										</div>
									)}
								</td>
								<td>
									<div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--ink-1)" }}>
										{fmtNum(h.encounter_count)}
										{h.phase_count > 0 && <span style={{ color: "var(--violet)", marginLeft: 6 }}>(Phase {h.phase_count + 1})</span>}
									</div>
									<div style={{ fontSize: 11, color: "var(--ink-3)", marginTop: 2 }}>
										{getLuckLabel(youP)}
									</div>
								</td>
								<td>
									{h.status === "completed" ? (
										<span className="phase-pill" style={{ background: "var(--green-soft)", color: "var(--green)", borderColor: "var(--green-line)" }}>
											Caught
										</span>
									) : (
										<span className="phase-pill">Active</span>
									)}
								</td>
								<td>
									<button className="timer-link" style={{ color: "var(--red)" }} onClick={() => onDelete(h.id)}>
										delete
									</button>
								</td>
							</tr>
						);
					})}
				</tbody>
			</table>
		</div>
	);
}
