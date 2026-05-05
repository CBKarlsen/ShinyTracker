import { createTheme } from "@mui/material/styles";
import { colors } from "./palette";

/**
 * MUI theme — colors are sourced from palette.ts.
 * Do not hardcode hex values here; reference `colors.*` instead.
 */
const theme = createTheme({
	palette: {
		mode: "light",
		primary: {
			main: colors.primary,
			light: colors.primaryLight,
		},
		secondary: {
			main: colors.accent,
		},
		background: {
			default: colors.bgDefault,
			paper: colors.bgPaper,
		},
		text: {
			primary: colors.textPrimary,
			secondary: colors.textSecondary,
		},
		success: {
			main: colors.success,
		},
		error: {
			main: colors.error,
		},
		warning: {
			main: colors.warning,
		},
		divider: colors.border,
	},
	typography: {
		fontFamily: '"Inter", "Roboto", "Helvetica", "Arial", sans-serif',
		h1: {
			fontSize: "2.5rem",
			fontWeight: 700,
			color: colors.textPrimary,
		},
		h2: {
			fontSize: "2rem",
			fontWeight: 600,
			color: colors.textPrimary,
		},
		h4: {
			fontWeight: 600,
			color: colors.textPrimary,
		},
		h6: {
			fontWeight: 600,
		},
	},
	components: {
		MuiCard: {
			styleOverrides: {
				root: {
					borderRadius: 16,
					backgroundImage: "none",
					backgroundColor: colors.bgPaper,
					border: `1px solid ${colors.border}`,
					boxShadow:
						"0 2px 8px -2px rgba(116,141,174,0.12), 0 1px 4px -1px rgba(116,141,174,0.08)",
					transition: "transform 0.2s ease-in-out, box-shadow 0.2s ease-in-out",
					"&:hover": {
						transform: "translateY(-3px)",
						boxShadow:
							"0 8px 24px -4px rgba(116,141,174,0.18), 0 4px 8px -2px rgba(116,141,174,0.10)",
					},
				},
			},
		},
		MuiButton: {
			styleOverrides: {
				root: {
					borderRadius: 8,
					textTransform: "none",
					fontWeight: 600,
				},
			},
		},
		MuiChip: {
			styleOverrides: {
				root: {
					borderRadius: 8,
				},
			},
		},
		MuiPaper: {
			styleOverrides: {
				root: {
					backgroundImage: "none",
				},
			},
		},
	},
});

export default theme;
