import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import CssBaseline from "@mui/material/CssBaseline";
import { ThemeProvider } from "@mui/material/styles";
import App from "./App.tsx";
import { AuthProvider } from "./context/AuthContext";
import theme from "./theme";

createRoot(document.getElementById("root")!).render(
	<StrictMode>
		<AuthProvider>
			<ThemeProvider theme={theme}>
				<CssBaseline />
				<App />
			</ThemeProvider>
		</AuthProvider>
	</StrictMode>,
);
