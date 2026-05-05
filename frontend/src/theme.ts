import { createTheme } from "@mui/material/styles";
import { colors } from "./palette";

/**
 * MUI theme — colors are sourced from palette.ts.
 * Do not hardcode hex values here; reference `colors.*` instead.
 */
const theme = createTheme({
	palette: {
		mode: "dark",
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
					borderRadius: 12,
					backgroundImage: "none",
					backgroundColor: colors.bgPaper,
					border: `1px solid ${colors.border}`,
					boxShadow: "0 2px 8px -2px rgba(0,0,0,0.4)",
					transition: "background-color 0.18s ease, box-shadow 0.18s ease",
					"&:hover": {
						backgroundColor: colors.bgSubtle,
						boxShadow: "0 6px 20px -4px rgba(0,0,0,0.5)",
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
		MuiAutocomplete: {
			styleOverrides: {
				paper: {
					backgroundColor: colors.bgPaper,
					backgroundImage: "none",
					border: `1px solid ${colors.border}`,
					boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
				},
				listbox: {
					backgroundColor: colors.bgPaper,
					padding: "4px",
				},
				option: {
					color: colors.textPrimary,
					borderRadius: "6px",
					"&:hover": {
						backgroundColor: colors.bgSubtle,
					},
					'&[aria-selected="true"]': {
						backgroundColor: `${colors.primary}22`,
					},
					'&[aria-selected="true"]:hover': {
						backgroundColor: `${colors.primary}33`,
					},
				},
				noOptions: {
					color: colors.textSecondary,
				},
			},
		},
	},
});

export default theme;
