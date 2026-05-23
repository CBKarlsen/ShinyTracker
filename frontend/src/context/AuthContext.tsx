import type React from "react";
import { createContext, useContext, useEffect, useState } from "react";

interface AuthContextType {
	token: string | null;
	userId: string | null;
	username: string | null;
	isAdmin: boolean;
	login: (token: string, userId: string, username?: string) => void;
	logout: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({
	children,
}) => {
	const [token, setToken] = useState<string | null>(
		localStorage.getItem("token"),
	);
	const [userId, setUserId] = useState<string | null>(
		localStorage.getItem("userId"),
	);
	const [username, setUsername] = useState<string | null>(
		localStorage.getItem("username"),
	);
	const [isAdmin, setIsAdmin] = useState(false);

	useEffect(() => {
		if (!token) {
			setIsAdmin(false);
			setUsername(null);
			return;
		}
		fetch("http://localhost:8080/api/me", {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((r) => {
				if (r.status === 401) {
					localStorage.removeItem("token");
					localStorage.removeItem("userId");
					localStorage.removeItem("username");
					setToken(null);
					setUserId(null);
					setUsername(null);
					setIsAdmin(false);
					return null;
				}
				return r.ok ? r.json() : null;
			})
			.then((data) => {
				if (data) {
					setIsAdmin(data.is_admin ?? false);
					if (data.username) {
						setUsername(data.username);
						localStorage.setItem("username", data.username);
					}
				}
			})
			.catch((err) => {
				console.error("Failed to fetch current user info", err);
			});
	}, [token]);

	const login = (newToken: string, newUserId: string, newUsername?: string) => {
		localStorage.setItem("token", newToken);
		localStorage.setItem("userId", newUserId);
		if (newUsername) {
			localStorage.setItem("username", newUsername);
			setUsername(newUsername);
		}
		setToken(newToken);
		setUserId(newUserId);
	};

	const logout = () => {
		localStorage.removeItem("token");
		localStorage.removeItem("userId");
		localStorage.removeItem("username");
		setToken(null);
		setUserId(null);
		setUsername(null);
		setIsAdmin(false);
	};

	return (
		<AuthContext.Provider
			value={{ token, userId, username, isAdmin, login, logout }}
		>
			{children}
		</AuthContext.Provider>
	);
};

export const useAuth = () => {
	const context = useContext(AuthContext);
	if (!context) throw new Error("useAuth must be used within an AuthProvider");
	return context;
};
