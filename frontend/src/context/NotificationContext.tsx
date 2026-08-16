import { Alert, Snackbar } from "@mui/material";
import type React from "react";
import { createContext, useCallback, useContext, useMemo, useState } from "react";

interface NotificationContextType {
	showError: (message: string) => void;
	showSuccess: (message: string) => void;
	showInfo: (message: string) => void;
}

const NotificationContext = createContext<NotificationContextType | null>(null);

export const NotificationProvider: React.FC<{ children: React.ReactNode }> = ({
	children,
}) => {
	const [open, setOpen] = useState(false);
	const [message, setMessage] = useState("");
	const [severity, setSeverity] = useState<"success" | "error" | "info">(
		"success",
	);

	// Every one of these is memoized, and so is the context value below. That is
	// not a micro-optimisation — it is load-bearing.
	//
	// These functions are dependencies of `useEffect`s that fetch. Unmemoized,
	// each one is a new closure on every render of this provider, so the value
	// object is new too, so every consumer's effect re-runs. An effect whose
	// catch block calls `showError` then loops forever: fetch fails → toast →
	// provider re-renders → identity changes → effect re-runs → fetch fails.
	// Callers used to work around this by omitting them from dependency arrays,
	// which is a lint suppression at every call site instead of a fix at the one
	// place that causes it. `setState` setters are stable, so [] is correct here.
	const showError = useCallback((msg: string) => {
		setMessage(msg);
		setSeverity("error");
		setOpen(true);
	}, []);

	const showSuccess = useCallback((msg: string) => {
		setMessage(msg);
		setSeverity("success");
		setOpen(true);
	}, []);

	const showInfo = useCallback((msg: string) => {
		setMessage(msg);
		setSeverity("info");
		setOpen(true);
	}, []);

	const value = useMemo(
		() => ({ showError, showSuccess, showInfo }),
		[showError, showSuccess, showInfo],
	);

	const handleClose = (
		_event?: React.SyntheticEvent | Event,
		reason?: string,
	) => {
		if (reason === "clickaway") {
			return;
		}
		setOpen(false);
	};

	return (
		<NotificationContext.Provider value={value}>
			{children}
			<Snackbar
				open={open}
				autoHideDuration={4000}
				onClose={handleClose}
				anchorOrigin={{ vertical: "top", horizontal: "right" }}
			>
				<Alert
					onClose={handleClose}
					severity={severity}
					variant="filled"
					sx={{
						width: "100%",
						fontFamily: "var(--font-mono)",
						fontSize: "12px",
						borderRadius: "8px",
						boxShadow: "0 8px 32px rgba(0, 0, 0, 0.4)",
					}}
				>
					{message}
				</Alert>
			</Snackbar>
		</NotificationContext.Provider>
	);
};

export const useNotification = () => {
	const context = useContext(NotificationContext);
	if (!context)
		throw new Error(
			"useNotification must be used within a NotificationProvider",
		);
	return context;
};
