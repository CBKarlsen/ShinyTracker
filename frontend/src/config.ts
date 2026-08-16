if (import.meta.env.PROD && !import.meta.env.VITE_API_URL) {
	throw new Error(
		"VITE_API_URL is not set. A production build must not silently fall " +
			"back to http://localhost:8080 — set it as a Railway build arg " +
			"(see docs/DEPLOY.md).",
	);
}

export const API_BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8080";
