import type React from "react";
import { createContext, useContext, useState, useEffect } from "react";

interface AuthContextType {
	token: string | null;
	userId: string | null;
	isAdmin: boolean;
	login: (token: string, userId: string) => void;
	logout: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
	const [token, setToken] = useState<string | null>(localStorage.getItem("token"));
	const [userId, setUserId] = useState<string | null>(localStorage.getItem("userId"));
	const [isAdmin, setIsAdmin] = useState(false);

	useEffect(() => {
		if (!token) { setIsAdmin(false); return; }
		fetch("http://localhost:8080/api/me", {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((r) => r.ok ? r.json() : null)
			.then((data) => setIsAdmin(data?.is_admin ?? false))
			.catch(() => setIsAdmin(false));
	}, [token]);

	const login = (newToken: string, newUserId: string) => {
		localStorage.setItem("token", newToken);
		localStorage.setItem("userId", newUserId);
		setToken(newToken);
		setUserId(newUserId);
	};

	const logout = () => {
		localStorage.removeItem("token");
		localStorage.removeItem("userId");
		setToken(null);
		setUserId(null);
		setIsAdmin(false);
	};

	return (
		<AuthContext.Provider value={{ token, userId, isAdmin, login, logout }}>
			{children}
		</AuthContext.Provider>
	);
};

export const useAuth = () => {
	const context = useContext(AuthContext);
	if (!context) throw new Error("useAuth must be used within an AuthProvider");
	return context;
};
