import type React from "react";
import { useState } from "react";
import { useAuth } from "../context/AuthContext";

const SparkSm = ({ size = 18, color }: { size?: number; color?: string }) => (
	<svg viewBox="0 0 12 12" width={size} height={size} aria-hidden>
		<path d="M6 0 L7 5 L12 6 L7 7 L6 12 L5 7 L0 6 L5 5 Z" fill={color || "currentColor"} />
	</svg>
);

const Login: React.FC = () => {
	const [mode, setMode] = useState<"login" | "register">("login");
	const [username, setUsername] = useState("");
	const [email, setEmail] = useState("");
	const [password, setPassword] = useState("");
	const [error, setError] = useState<string | null>(null);
	const { login } = useAuth();

	const handleSubmit = async (e: React.FormEvent) => {
		e.preventDefault();
		setError(null);
		const endpoint = mode === "login" ? "/api/auth/login" : "/api/auth/register";
		const body = mode === "login" ? { email, password } : { username, email, password };

		try {
			const res = await fetch(`http://localhost:8080${endpoint}`, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify(body),
			});

			if (!res.ok) throw new Error("Authentication failed");

			if (mode === "register") {
				setMode("login");
				setError("Registered! Please sign in.");
				return;
			}

			const data = await res.json();
			login(data.token, data.user.id);
		} catch {
			setError("Invalid credentials or email already taken.");
		}
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
								background: "radial-gradient(circle at 30% 30%, var(--gold-soft), transparent 60%)",
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

				<div className="login-tabs">
					<button className={mode === "login" ? "on" : ""} onClick={() => setMode("login")}>
						Sign in
					</button>
					<button className={mode === "register" ? "on" : ""} onClick={() => setMode("register")}>
						Register
					</button>
				</div>

				{error && (
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							padding: "8px 12px",
							borderRadius: 6,
							marginBottom: 12,
							background: error.startsWith("Registered") ? "var(--green-soft)" : "var(--red-soft)",
							color: error.startsWith("Registered") ? "var(--green)" : "var(--red)",
							border: `1px solid ${error.startsWith("Registered") ? "var(--green)" : "var(--red)"}`,
						}}
					>
						{error}
					</div>
				)}

				<form onSubmit={handleSubmit}>
					{mode === "register" && (
						<div className="field">
							<label>Username</label>
							<input
								className="input"
								placeholder="trainer_name"
								value={username}
								onChange={(e) => setUsername(e.target.value)}
								required
							/>
						</div>
					)}
					<div className="field">
						<label>Email</label>
						<input
							className="input"
							type="email"
							placeholder="you@example.com"
							value={email}
							onChange={(e) => setEmail(e.target.value)}
							required
						/>
					</div>
					<div className="field">
						<label>Password</label>
						<input
							className="input"
							type="password"
							placeholder="••••••••"
							value={password}
							onChange={(e) => setPassword(e.target.value)}
							required
						/>
					</div>
					<button
						className="btn gold"
						style={{ width: "100%", justifyContent: "center", marginTop: 8 }}
						type="submit"
					>
						{mode === "login" ? "Sign in" : "Create account"}
						<span style={{ opacity: 0.5 }}>→</span>
					</button>
				</form>

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
					{mode === "login"
						? "Track your shiny journey"
						: "By registering you accept the ToS."}
				</div>
			</div>
		</div>
	);
};

export default Login;
