export function Stat({ label, value, unit, accent }: { label: string; value: string | number; unit?: string; accent?: string }) {
	return (
		<div className="stat-tile">
			<div className="t-label">{label}</div>
			<div className="v" style={accent ? { color: accent } : undefined}>
				{value}
				{unit && <span className="unit">{unit}</span>}
			</div>
		</div>
	);
}
