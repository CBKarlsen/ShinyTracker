import { IcPlay, IcPause } from "./icons";

export type TimerStatus = "live" | "idle" | "paused";

export function TimerDisplay({
	sessionSec,
	totalSec,
	status,
	onToggle,
	onReset,
	pacePerHour,
}: {
	sessionSec: number;
	totalSec: number;
	status: TimerStatus;
	onToggle: () => void;
	onReset: () => void;
	pacePerHour?: number | null;
}) {
	const m = Math.floor(sessionSec / 60);
	const s = sessionSec % 60;
	const hh = Math.floor(m / 60);
	const mm = m % 60;
	const display =
		hh > 0
			? `${hh}:${String(mm).padStart(2, "0")}:${String(s).padStart(2, "0")}`
			: `${String(mm).padStart(2, "0")}:${String(s).padStart(2, "0")}`;

	const labels: Record<TimerStatus, string> = {
		live: "recording",
		idle: "idle · auto-paused",
		paused: "paused",
	};

	const fmtHM = (sec: number) => {
		const h = Math.floor(sec / 3600);
		const min = Math.floor((sec % 3600) / 60);
		if (h > 0) return `${h}h ${min}m`;
		return `${min}m`;
	};

	return (
		<div className="timer-display">
			<div className="timer-row">
				<span className={`timer-dot timer-dot-${status}`} />
				<span className="timer-clock">{display}</span>
				<button
					type="button"
					className="timer-btn"
					onClick={onToggle}
					title={status === "paused" ? "Resume" : "Pause"}
					aria-label={status === "paused" ? "Resume session timer" : "Pause session timer"}
				>
					{status === "paused" ? <IcPlay /> : <IcPause />}
				</button>
			</div>
			<div className="timer-meta">
				<span>session · {labels[status]}</span>
				{sessionSec > 0 && status !== "live" && (
					<button className="timer-link" onClick={onReset} title="Reset session timer">
						reset
					</button>
				)}
			</div>
			<div className="timer-meta" style={{ marginTop: 2 }}>
				<span>total · {fmtHM(totalSec)}</span>
			</div>
			{pacePerHour != null && (
				<div className="timer-meta" style={{ marginTop: 2 }}>
					<span>pace · {pacePerHour === -1 ? "—" : `≈ ${pacePerHour.toLocaleString("en-US")} /h`}</span>
				</div>
			)}
		</div>
	);
}
