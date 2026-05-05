import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import CssBaseline from "@mui/material/CssBaseline";
import { ThemeProvider } from "@mui/material/styles";
import App from "./App.tsx";
import { AuthProvider } from "./context/AuthContext";
import theme from "./theme";
import { cssVars } from "./palette";

// Inject palette as CSS custom properties on :root before first render.
// To retheme: edit palette.ts — changes here are automatic.
const root = document.documentElement;
Object.entries(cssVars).forEach(([key, value]) => {
	root.style.setProperty(`--color-${key}`, value);
});

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
