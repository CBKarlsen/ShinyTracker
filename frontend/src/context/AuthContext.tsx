import type { Session } from "@supabase/supabase-js";
import type React from "react";
import {
	createContext,
	useCallback,
	useContext,
	useEffect,
	useMemo,
	useState,
} from "react";
import { API_BASE } from "../config";
import { supabase } from "../lib/supabase";

interface AuthContextType {
	token: string | null;
	userId: string | null;
	username: string | null;
	isAdmin: boolean;
	loading: boolean;
	login: (token: string, userId: string, username?: string) => void;
	logout: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

function usernameFromSession(session: Session | null): string | null {
	if (!session) return null;
	const meta = session.user?.user_metadata ?? {};
	return (
		(meta.user_name as string | undefined) ??
		(meta.name as string | undefined) ??
		(meta.full_name as string | undefined) ??
		session.user?.email ??
		null
	);
}

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({
	children,
}) => {
	const [session, setSession] = useState<Session | null>(null);
	const [username, setUsername] = useState<string | null>(null);
	const [isAdmin, setIsAdmin] = useState(false);
	// loading stays true until the initial getSession() resolves so we never
	// flash the login screen for an already-authenticated user.
	const [loading, setLoading] = useState(true);

	// Derive token + userId directly from the Supabase session.
	const token = session?.access_token ?? null;
	const userId = session?.user?.id ?? null;

	// Once we have a session, hit /api/me to trigger the backend profile upsert
	// and pick up the canonical username + is_admin flag.
	useEffect(() => {
		if (!token) {
			setIsAdmin(false);
			// Don't clear username here — onAuthStateChange will handle it when
			// the session actually goes away.
			return;
		}

		fetch(`${API_BASE}/api/me`, {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((r) => {
				if (r.status === 401) {
					supabase.auth.signOut();
					return null;
				}
				return r.ok ? r.json() : null;
			})
			.then((data) => {
				if (data) {
					setIsAdmin(data.is_admin ?? false);
					if (data.username) {
						setUsername(data.username);
					}
				}
			})
			.catch((err) => {
				console.error("Failed to fetch current user info", err);
			});
	}, [token]);

	// Bootstrap: get the current session once on mount, then subscribe to changes.
	useEffect(() => {
		supabase.auth.getSession().then(({ data }) => {
			const s = data.session ?? null;
			setSession(s);
			if (!s) {
				// No session — set username from metadata (will be null), clear admin.
				setUsername(null);
				setIsAdmin(false);
			} else {
				setUsername(usernameFromSession(s));
			}
			setLoading(false);
		});

		const {
			data: { subscription },
		} = supabase.auth.onAuthStateChange((_event, newSession) => {
			setSession(newSession);
			if (newSession) {
				setUsername(usernameFromSession(newSession));
			} else {
				setUsername(null);
				setIsAdmin(false);
			}
		});

		return () => subscription.unsubscribe();
	}, []);

	// Kept for interface compatibility — no-op in the OAuth flow; callers that
	// relied on this (old email/password Login) no longer exist, but other code
	// that imports the shape won't break.
	const login = useCallback(
		(_newToken: string, _newUserId: string, _newUsername?: string) => {
			// Session is managed entirely by supabase-js; nothing to do here.
		},
		[],
	);

	const logout = useCallback(async () => {
		await supabase.auth.signOut();
		// onAuthStateChange will fire and clear session/username/isAdmin.
	}, []);

	// Memoized for the same load-bearing reason as NotificationContext's: these
	// are dependencies of fetching effects across the app. An unstable `logout`
	// makes every `handleSessionExpired` unstable, which re-runs the effect that
	// depends on it — and one of those effects raises a toast on failure, which
	// re-renders a provider, which starts the loop again.
	const value = useMemo(
		() => ({ token, userId, username, isAdmin, loading, login, logout }),
		[token, userId, username, isAdmin, loading, login, logout],
	);

	return (
		<AuthContext.Provider value={value}>
			{children}
		</AuthContext.Provider>
	);
};

export const useAuth = () => {
	const context = useContext(AuthContext);
	if (!context) throw new Error("useAuth must be used within an AuthProvider");
	return context;
};
