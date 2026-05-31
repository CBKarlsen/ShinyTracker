/**
 * Shared authenticated fetch wrapper.
 *
 * Sends the Authorization header automatically and centrally handles 401
 * responses: when the server rejects the token, it calls onSessionExpired
 * (which should log the user out) and throws a SessionExpiredError so call
 * sites can distinguish session expiry from other network failures.
 */

export class SessionExpiredError extends Error {
	constructor() {
		super("session_expired");
		this.name = "SessionExpiredError";
	}
}

export async function authedFetch(
	url: string,
	token: string | null,
	options: RequestInit = {},
	onSessionExpired?: () => void,
): Promise<Response> {
	const headers = new Headers(options.headers);
	if (token) {
		headers.set("Authorization", `Bearer ${token}`);
	}

	const res = await fetch(url, { ...options, headers });

	if (res.status === 401) {
		if (onSessionExpired) onSessionExpired();
		throw new SessionExpiredError();
	}

	return res;
}
