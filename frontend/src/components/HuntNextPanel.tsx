import type React from "react";
import { useCallback, useEffect, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import type {
	HuntSuggestion,
	HuntSuggestionsResponse,
	Pokemon,
	PokemonRoute,
} from "../types/models";
import { authedFetch, SessionExpiredError } from "../utils/authedFetch";

const HuntNextPanel: React.FC<{
	onStart: (pokemon: Pokemon, route: PokemonRoute) => void;
	onOpen: (pokemonId: number) => void;
}> = ({ onStart, onOpen }) => {
	const { token, logout } = useAuth();
	const { showError } = useNotification();
	const [data, setData] = useState<HuntSuggestionsResponse | null>(null);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState(false);

	const handleSessionExpired = useCallback(() => {
		logout();
		showError("Your session expired — please sign in again.");
	}, [logout, showError]);

	useEffect(() => {
		let cancelled = false;
		setLoading(true);
		setError(false);
		authedFetch(
			`${API_BASE}/api/dex/suggestions`,
			token,
			{},
			handleSessionExpired,
		)
			.then((res) => {
				if (!res.ok) throw new Error("failed");
				return res.json();
			})
			.then((d: HuntSuggestionsResponse) => {
				if (!cancelled) setData(d);
			})
			.catch((err) => {
				if (err instanceof SessionExpiredError) return;
				if (!cancelled) setError(true);
			})
			.finally(() => {
				if (!cancelled) setLoading(false);
			});
		return () => {
			cancelled = true;
		};
	}, [token, handleSessionExpired]);

	if (error) return null;

	if (loading) {
		return (
			<section className="hunt-next">
				<h2 className="hunt-next-title">Hunt next</h2>
				<div className="hunt-next-grid">
					{Array.from({ length: 12 }).map((_, i) => (
						<div key={i} className="hunt-next-card hunt-next-card--skeleton" />
					))}
				</div>
			</section>
		);
	}

	if (!data || data.total_huntable === 0) {
		return (
			<section className="hunt-next">
				<h2 className="hunt-next-title">Hunt next</h2>
				<p className="hunt-next-empty">
					No huntable targets left — your dex is complete or the rest are
					blocked 🎉
				</p>
			</section>
		);
	}

	return (
		<section className="hunt-next">
			<h2 className="hunt-next-title">
				Hunt next{" "}
				<span className="hunt-next-count">
					· {data.total_huntable} huntable targets left
				</span>
			</h2>
			<div className="hunt-next-grid">
				{data.suggestions.map((s) => (
					<HuntNextCard
						key={s.pokemon_id}
						s={s}
						onStart={onStart}
						onOpen={onOpen}
					/>
				))}
			</div>
		</section>
	);
};

const HuntNextCard: React.FC<{
	s: HuntSuggestion;
	onStart: (pokemon: Pokemon, route: PokemonRoute) => void;
	onOpen: (pokemonId: number) => void;
}> = ({ s, onStart, onOpen }) => {
	const r = s.route;
	const constrained = s.huntable_game_count === 1;
	return (
		<div
			className="hunt-next-card"
			onClick={() => onOpen(s.pokemon_id)}
			onKeyDown={(e) => {
				if (e.key === "Enter") onOpen(s.pokemon_id);
			}}
			role="button"
			tabIndex={0}
		>
			<div className="hunt-next-card-top">
				<img
					className="hunt-next-sprite"
					src={s.sprite_url}
					alt={s.name}
					loading="lazy"
				/>
				<span
					className={`hunt-next-badge${constrained ? " hunt-next-badge--hot" : ""}`}
				>
					{constrained ? "only 1 game" : `${s.huntable_game_count} games`}
				</span>
			</div>
			<div className="hunt-next-name">{s.name}</div>
			<div className="hunt-next-meta">
				{r.game_title} · {r.method_name}
			</div>
			<div className="hunt-next-odds">
				1 / {r.odds.toLocaleString()}{" "}
				<span className="hunt-next-eta">· ~{r.eta_hours.toFixed(1)} h</span>
			</div>
			<button
				type="button"
				className="hunt-next-start"
				onClick={(e) => {
					e.stopPropagation();
					onStart(
						{ id: s.pokemon_id, name: s.name, sprite_url: s.sprite_url },
						r,
					);
				}}
			>
				Start
			</button>
		</div>
	);
};

export default HuntNextPanel;
