import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App.tsx";
import { ErrorBoundary } from "./components/ErrorBoundary";
import { AuthProvider } from "./context/AuthContext";
import { NotificationProvider } from "./context/NotificationContext";

createRoot(document.getElementById("root")!).render(
	<StrictMode>
		<ErrorBoundary>
			<AuthProvider>
				<NotificationProvider>
					<App />
				</NotificationProvider>
			</AuthProvider>
		</ErrorBoundary>
	</StrictMode>,
);
