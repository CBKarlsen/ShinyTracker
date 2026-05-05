import {
	Box,
	Button,
	Card,
	CardContent,
	TextField,
	Typography,
} from "@mui/material";
import type React from "react";
import { useState } from "react";
import { useAuth } from "../context/AuthContext";

const Login: React.FC = () => {
	const [isLogin, setIsLogin] = useState(true);
	const [username, setUsername] = useState("");
	const [email, setEmail] = useState("");
	const [password, setPassword] = useState("");
	const { login } = useAuth();

	const handleSubmit = async (e: React.FormEvent) => {
		e.preventDefault();
		const endpoint = isLogin ? "/api/auth/login" : "/api/auth/register";
		const body = isLogin ? { email, password } : { username, email, password };

		try {
			const res = await fetch(`http://localhost:8080${endpoint}`, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify(body),
			});

			if (!res.ok) throw new Error("Authentication failed");

			if (!isLogin) {
				// If registered, switch to login
				setIsLogin(true);
				alert("Registered! Please log in.");
				return;
			}

			const data = await res.json();
			login(data.token, data.user.id);
		} catch (err) {
			alert("Error: Invalid credentials or email taken.");
		}
	};

	return (
		<Box
			sx={{
				display: "flex",
				justifyContent: "center",
				alignItems: "center",
				height: "80vh",
			}}
		>
			<Card sx={{ width: 400, p: 2 }}>
				<CardContent>
					<Typography variant="h5" gutterBottom>
						{isLogin ? "Login" : "Register"}
					</Typography>
					<form onSubmit={handleSubmit}>
						{!isLogin && (
							<TextField
								fullWidth
								label="Username"
								margin="normal"
								value={username}
								onChange={(e) => setUsername(e.target.value)}
								required
							/>
						)}
						<TextField
							fullWidth
							label="Email"
							type="email"
							margin="normal"
							value={email}
							onChange={(e) => setEmail(e.target.value)}
							required
						/>
						<TextField
							fullWidth
							label="Password"
							type="password"
							margin="normal"
							value={password}
							onChange={(e) => setPassword(e.target.value)}
							required
						/>
						<Button fullWidth variant="contained" type="submit" sx={{ mt: 2 }}>
							{isLogin ? "Login" : "Register"}
						</Button>
						<Button
							fullWidth
							color="secondary"
							onClick={() => setIsLogin(!isLogin)}
							sx={{ mt: 1 }}
						>
							{isLogin
								? "Need an account? Register"
								: "Already have an account? Login"}
						</Button>
					</form>
				</CardContent>
			</Card>
		</Box>
	);
};

export default Login;
