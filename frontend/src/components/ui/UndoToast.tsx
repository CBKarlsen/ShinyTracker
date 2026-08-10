import { IcClose } from "./icons";

interface Props {
	message: string;
	onUndo: () => void;
	onDismiss: () => void;
}

/**
 * Floating toast for reversible actions: coalesced increment bursts, chain
 * resets, direct count edits. `role="status"` makes the message an implicit
 * polite live region, so it's announced without stealing focus.
 *
 * The undo action itself goes through the same optimistic-update + PATCH
 * path as everything else — it can fail and roll back like any other write.
 */
export function UndoToast({ message, onUndo, onDismiss }: Props) {
	return (
		<div className="undo-toast" role="status">
			<span className="undo-toast-message">{message}</span>
			<button type="button" className="undo-toast-action" onClick={onUndo}>
				Undo
			</button>
			<button
				type="button"
				className="undo-toast-dismiss"
				onClick={onDismiss}
				aria-label="Dismiss"
			>
				<IcClose />
			</button>
		</div>
	);
}
