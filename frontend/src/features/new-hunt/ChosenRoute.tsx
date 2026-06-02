import { HuntParametersEditor } from "../../components/ui/HuntParametersEditor";
import type { PokemonRoute } from "../../types/models";

interface Props {
	route: PokemonRoute;
	huntParams: Record<string, unknown>;
	setHuntParams: (params: Record<string, unknown>) => void;
	onChange: () => void;
}

/**
 * Compact confirmation for an already-chosen route: method + game + odds/eta,
 * the parameter inputs (if the formula needs them), and a "Change method" link.
 * Replaces the full RouteList in the prefill path so the user isn't re-asked
 * the choice they just made.
 */
export function ChosenRoute({
	route,
	huntParams,
	setHuntParams,
	onChange,
}: Props) {
	return (
		<div
			style={{
				padding: 16,
				background: "var(--bg-2)",
				border: "1px solid var(--line-1)",
				borderRadius: 12,
				marginBottom: 4,
			}}
		>
			<div style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
				<div style={{ flex: 1 }}>
					<div
						style={{
							fontFamily: "var(--font-display)",
							fontSize: 15,
							fontWeight: 600,
						}}
					>
						{route.method_name}
					</div>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 10.5,
							color: "var(--ink-3)",
							marginTop: 2,
						}}
					>
						{route.evolve_from
							? `${route.evolve_from.name} · ${route.game_title}`
							: route.game_title}
					</div>
					{route.evolve_from && (
						<div className="dex-route-evo">↳ then evolve</div>
					)}
				</div>
				<button
					type="button"
					className="btn ghost"
					style={{ fontSize: 11 }}
					onClick={onChange}
				>
					Change method
				</button>
			</div>

			<div
				style={{
					display: "grid",
					gridTemplateColumns: "1fr 1fr",
					gap: 8,
					marginTop: 14,
					paddingTop: 14,
					borderTop: "1px solid var(--line-1)",
				}}
			>
				<div>
					<div className="t-label">Odds (best case)</div>
					<div
						className="t-mono"
						style={{
							fontSize: 13,
							marginTop: 2,
							color: "var(--gold)",
							fontWeight: 600,
						}}
					>
						1 / {route.odds.toLocaleString()}
					</div>
				</div>
				<div>
					<div className="t-label">ETA expected</div>
					<div className="t-mono" style={{ fontSize: 13, marginTop: 2 }}>
						~{route.eta_hours.toFixed(1)} h
					</div>
				</div>
			</div>

			<HuntParametersEditor
				formulaType={route.formula_type}
				huntParams={huntParams}
				setHuntParams={setHuntParams}
			/>
		</div>
	);
}
