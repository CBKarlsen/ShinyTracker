import type React from "react";
import { useState } from "react";
import { supabase } from "../lib/supabase";

const SparkSm = ({ size = 18, color }: { size?: number; color?: string }) => (
	<svg viewBox="0 0 12 12" width={size} height={size} aria-hidden>
		<path
			d="M6 0 L7 5 L12 6 L7 7 L6 12 L5 7 L0 6 L5 5 Z"
			fill={color || "currentColor"}
		/>
	</svg>
);

const GitHubIcon = () => (
	<svg
		viewBox="0 0 24 24"
		width={18}
		height={18}
		fill="currentColor"
		aria-hidden
	>
		<path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
	</svg>
);

const GoogleIcon = () => (
	<svg
		viewBox="0 0 24 24"
		width={18}
		height={18}
		fill="currentColor"
		aria-hidden
	>
		<path
			d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
			fill="#4285F4"
		/>
		<path
			d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
			fill="#34A853"
		/>
		<path
			d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z"
			fill="#FBBC05"
		/>
		<path
			d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
			fill="#EA4335"
		/>
	</svg>
);

type Provider = "github" | "google";

const Login: React.FC = () => {
	const [error, setError] = useState<string | null>(null);
	const [pending, setPending] = useState<Provider | null>(null);

	const handleOAuth = async (provider: Provider) => {
		setError(null);
		setPending(provider);
		const { error: oauthError } = await supabase.auth.signInWithOAuth({
			provider,
			options: { redirectTo: window.location.origin },
		});
		if (oauthError) {
			setError(oauthError.message || "Failed to start sign-in. Please try again.");
			setPending(null);
		}
		// On success the browser is redirected; no state update needed here.
	};

	return (
		<div className="login-shell">
			<div className="login-card">
				<div className="brand">
					<div
						style={{
							width: 36,
							height: 36,
							borderRadius: 9,
							background: "linear-gradient(135deg, #1A1A24 0%, #0F0F18 100%)",
							border: "1px solid var(--line-2)",
							display: "grid",
							placeItems: "center",
							position: "relative",
							overflow: "hidden",
						}}
					>
						<div
							style={{
								position: "absolute",
								inset: 0,
								background:
									"radial-gradient(circle at 30% 30%, var(--gold-soft), transparent 60%)",
							}}
						/>
						<div style={{ position: "relative" }}>
							<SparkSm size={18} color="var(--gold)" />
						</div>
					</div>
					<div>
						<div className="nm">ShinyTracker</div>
						<div className="sub">Shiny Pokémon Tracker</div>
					</div>
				</div>

				{error && (
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							padding: "8px 12px",
							borderRadius: 6,
							marginBottom: 12,
							background: "var(--red-soft)",
							color: "var(--red)",
							border: "1px solid var(--red)",
						}}
					>
						{error}
					</div>
				)}

				<div
					style={{
						display: "flex",
						flexDirection: "column",
						gap: 10,
						marginTop: 8,
					}}
				>
					<button
						className="btn"
						style={{
							width: "100%",
							justifyContent: "center",
							gap: 10,
							opacity: pending && pending !== "github" ? 0.5 : 1,
						}}
						type="button"
						disabled={pending !== null}
						onClick={() => handleOAuth("github")}
					>
						<GitHubIcon />
						{pending === "github" ? "Redirecting…" : "Continue with GitHub"}
					</button>
					<button
						className="btn"
						style={{
							width: "100%",
							justifyContent: "center",
							gap: 10,
							opacity: pending && pending !== "google" ? 0.5 : 1,
						}}
						type="button"
						disabled={pending !== null}
						onClick={() => handleOAuth("google")}
					>
						<GoogleIcon />
						{pending === "google" ? "Redirecting…" : "Continue with Google"}
					</button>
				</div>

				<div
					style={{
						textAlign: "center",
						marginTop: 18,
						fontFamily: "var(--font-mono)",
						fontSize: 10.5,
						color: "var(--ink-3)",
						letterSpacing: "0.06em",
					}}
				>
					Track your shiny journey
				</div>
			</div>
		</div>
	);
};

export default Login;
