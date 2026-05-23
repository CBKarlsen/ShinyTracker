import { Alert, Snackbar } from "@mui/material";
import type React from "react";
import { createContext, useContext, useState } from "react";

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

	const showError = (msg: string) => {
		setMessage(msg);
		setSeverity("error");
		setOpen(true);
	};

	const showSuccess = (msg: string) => {
		setMessage(msg);
		setSeverity("success");
		setOpen(true);
	};

	const showInfo = (msg: string) => {
		setMessage(msg);
		setSeverity("info");
		setOpen(true);
	};

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
		<NotificationContext.Provider value={{ showError, showSuccess, showInfo }}>
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
