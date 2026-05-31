export const SparkSm = ({ size = 10, color: _color }: { size?: number; color?: string }) => (
	<img
		src="/shiny-charm.png"
		alt=""
		width={size}
		height={size}
		aria-hidden="true"
		style={{ display: "inline-block", objectFit: "contain", verticalAlign: "middle" }}
	/>
);

export const IcPlay = () => (
	<svg viewBox="0 0 16 16" width="11" height="11" fill="currentColor">
		<path d="M4 3l9 5-9 5z" />
	</svg>
);

export const IcPause = () => (
	<svg viewBox="0 0 16 16" width="11" height="11" fill="currentColor">
		<rect x="4" y="3" width="3" height="10" rx="0.5" />
		<rect x="9" y="3" width="3" height="10" rx="0.5" />
	</svg>
);

export const IcPin = () => (
	<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round">
		<path d="M8 1.5l2.4 4.3 2.6.6-1.8 2 .4 2.6L8 9.8 4.4 11l.4-2.6L3 6.4l2.6-.6L8 1.5z" />
	</svg>
);

export const IcPlus = () => (
	<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2">
		<path d="M8 3v10M3 8h10" />
	</svg>
);

export const IcClose = () => (
	<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5">
		<path d="M3 3l10 10M13 3L3 13" />
	</svg>
);
