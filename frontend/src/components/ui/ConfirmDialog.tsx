import { useEffect } from "react";
import { IcClose } from "./icons";

interface Props {
	open: boolean;
	title: string;
	message: string;
	confirmLabel?: string;
	cancelLabel?: string;
	onConfirm: () => void;
	onCancel: () => void;
	/** When true, the confirm button uses the danger/red accent. */
	danger?: boolean;
}

/**
 * Minimal confirmation dialog that matches the app's dark-theme drawer style.
 * Press Enter to confirm, Escape to cancel.
 */
export function ConfirmDialog({
	open,
	title,
	message,
	confirmLabel = "Confirm",
	cancelLabel = "Cancel",
	onConfirm,
	onCancel,
	danger = false,
}: Props) {
	useEffect(() => {
		if (!open) return;
		const onKey = (e: KeyboardEvent) => {
			if (e.key === "Enter") { e.preventDefault(); onConfirm(); }
			if (e.key === "Escape") { e.preventDefault(); onCancel(); }
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [open, onConfirm, onCancel]);

	if (!open) return null;

	return (
		<div className="scrim" onClick={onCancel} style={{ zIndex: 1100 }}>
			<div
				className="drawer"
				onClick={(e) => e.stopPropagation()}
				style={{ width: 380, maxWidth: "calc(100vw - 32px)" }}
			>
				<div className="drawer-head">
					<h2>{title}</h2>
					<button className="close" onClick={onCancel}>
						<IcClose />
					</button>
				</div>
				<div className="drawer-body">
					<p
						style={{
							margin: "0 0 24px",
							fontSize: 14,
							color: "var(--ink-2)",
							lineHeight: 1.6,
						}}
					>
						{message}
					</p>
					<div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
						<button className="btn ghost" onClick={onCancel}>
							{cancelLabel}
						</button>
						<button
							className="btn gold"
							onClick={onConfirm}
							autoFocus
							style={
								danger
									? {
											background: "var(--red, #e05252)",
											borderColor: "var(--red, #e05252)",
									  }
									: undefined
							}
						>
							{confirmLabel}
						</button>
					</div>
					<div
						style={{
							marginTop: 12,
							fontSize: 11,
							color: "var(--ink-4)",
							fontFamily: "var(--font-mono)",
							textAlign: "right",
						}}
					>
						Enter to confirm · Esc to cancel
					</div>
				</div>
			</div>
		</div>
	);
}
