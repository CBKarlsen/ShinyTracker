import type { Pokemon, HuntMethod } from "../../types/models";
import { HuntParametersEditor } from "../../components/ui/HuntParametersEditor";

interface Props {
	selectedPokemon: Pokemon;
	selectedMethod: HuntMethod | null;
	useCustomMethod: boolean;
	customMethodName: string;
	gifUrl: string;
	huntParams: Record<string, any>;
	setHuntParams: (params: Record<string, any>) => void;
	getBaseOdds: (gameTitle: string) => number;
	getOddsForMethod: (method: HuntMethod) => number;
}

export function MethodPreview({
	selectedPokemon,
	selectedMethod,
	useCustomMethod,
	customMethodName,
	gifUrl,
	huntParams,
	setHuntParams,
	getBaseOdds,
	getOddsForMethod,
}: Props) {
	if (!selectedMethod && !(useCustomMethod && customMethodName.trim())) {
		return null;
	}

	return (
		<div
			style={{
				padding: 16,
				background: "var(--bg-2)",
				border: "1px solid var(--line-1)",
				borderRadius: 12,
				marginTop: 18,
				marginBottom: 4,
			}}
		>
			<div style={{ display: "flex", gap: 14, alignItems: "center" }}>
				<div
					style={{
						width: 48,
						height: 48,
						background: "var(--bg-1)",
						border: "1px solid var(--line-1)",
						borderRadius: 8,
						display: "grid",
						placeItems: "center",
						position: "relative",
						overflow: "hidden",
					}}
				>
					<img
						src={gifUrl}
						alt={selectedPokemon.name}
						style={{
							width: 40,
							height: 40,
							imageRendering: "pixelated",
							objectFit: "contain",
						}}
						onError={(e) => {
							e.currentTarget.onerror = null;
							e.currentTarget.src = selectedPokemon.sprite_url;
						}}
					/>
				</div>
				<div>
					<div
						style={{
							fontFamily: "var(--font-display)",
							fontSize: 16,
							fontWeight: 600,
							letterSpacing: "-0.02em",
							textTransform: "capitalize",
							lineHeight: 1.2,
						}}
					>
						{selectedPokemon.name}
					</div>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 10.5,
							color: "var(--ink-3)",
							marginTop: 2,
						}}
					>
						{useCustomMethod
							? `Custom · ${customMethodName.trim()}`
							: `${selectedMethod!.game_title} · ${selectedMethod!.method_name}`}
					</div>
				</div>
			</div>
			{!useCustomMethod && selectedMethod && (
				<div
					style={{
						display: "grid",
						gridTemplateColumns: "1fr 1fr 1fr",
						gap: 8,
						marginTop: 14,
						paddingTop: 14,
						borderTop: "1px solid var(--line-1)",
					}}
				>
					<div>
						<div className="t-label">Base odds</div>
						<div className="t-mono" style={{ fontSize: 13, marginTop: 2 }}>
							1 / {getBaseOdds(selectedMethod.game_title).toLocaleString()}
						</div>
					</div>
					<div>
						<div className="t-label">Live Odds</div>
						<div
							className="t-mono"
							style={{
								fontSize: 13,
								marginTop: 2,
								color: "var(--gold)",
								fontWeight: 600,
							}}
						>
							1 / {getOddsForMethod(selectedMethod).toLocaleString()}
						</div>
					</div>
					<div>
						<div className="t-label">ETA expected</div>
						<div className="t-mono" style={{ fontSize: 13, marginTop: 2 }}>
							~
							{Math.round(
								(getOddsForMethod(selectedMethod) *
									selectedMethod.avg_time_seconds) /
									3600,
							)}
							h
						</div>
					</div>
				</div>
			)}
			<HuntParametersEditor
				formulaType={!useCustomMethod ? selectedMethod?.formula_type : null}
				huntParams={huntParams}
				setHuntParams={setHuntParams}
			/>
			{useCustomMethod && (
				<div
					style={{
						marginTop: 14,
						paddingTop: 14,
						borderTop: "1px solid var(--line-1)",
						fontSize: 11,
						color: "var(--ink-3)",
						fontFamily: "var(--font-mono)",
					}}
				>
					Custom method — no odds data
				</div>
			)}
		</div>
	);
}
