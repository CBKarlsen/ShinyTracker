import { useEffect, useState } from "react";
import { IcClose } from "../../components/ui/icons";
import type { Hunt, PokemonOption } from "../../types/models";
import { API_BASE } from "../../config";
import { useNotification } from "../../context/NotificationContext";

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

export function PhaseModal({ hunt, token, onClose, onSuccess }: {
	hunt: Hunt;
	token: string;
	onClose: () => void;
	onSuccess: (updated: Hunt) => void;
}) {
	const { showSuccess, showError } = useNotification();
	const [search, setSearch] = useState("");
	const [options, setOptions] = useState<PokemonOption[]>([]);
	const [submitting, setSubmitting] = useState(false);

	useEffect(() => {
		const timer = setTimeout(async () => {
			try {
				const res = await fetch(`${API_BASE}/api/pokemon?q=${search}`);
				if (res.ok) setOptions((await res.json()) || []);
			} catch { /* ignore */ }
		}, 300);
		return () => clearTimeout(timer);
	}, [search]);

	const handleSelect = async (pokemon: PokemonOption) => {
		setSubmitting(true);
		try {
			const res = await fetch(`${API_BASE}/api/hunts/${hunt.id}/phases`, {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({ pokemon_id: pokemon.id }),
			});
			if (res.ok) {
				const updated: Hunt = await res.json();
				showSuccess("Phase logged — counter reset");
				onSuccess(updated);
				onClose();
				return; // component unmounts — don't touch state below
			}
			showError("Failed to log phase. Please try again.");
		} catch {
			showError("Failed to log phase. Please try again.");
		}
		setSubmitting(false);
	};

	return (
		<div className="scrim" onClick={onClose}>
			<div className="drawer" onClick={(e) => e.stopPropagation()} style={{ width: 420 }}>
				<div className="drawer-head">
					<h2>Log phase</h2>
					<button className="close" onClick={onClose}>
						<IcClose />
					</button>
				</div>
				<div className="drawer-body">
					<div style={{ color: "var(--ink-3)", fontSize: 12.5, marginBottom: 16, lineHeight: 1.55 }}>
						Hunting <b style={{ color: "var(--ink-1)" }}>{hunt.pokemon_name}</b> — which shiny did you
						encounter? Your count of{" "}
						<b style={{ color: "var(--gold)" }}>{fmtNum(hunt.encounter_count)}</b> will be saved as a
						phase and reset to 0.
					</div>
					<div className="field">
						<label>Phase Pokémon</label>
						<input
							className="input"
							placeholder="Search…"
							value={search}
							onChange={(e) => setSearch(e.target.value)}
							autoFocus
						/>
					</div>
					<div className="poke-search-results">
						{options.slice(0, 8).map((p) => (
							<div
								key={p.id}
								className="row"
								onClick={() => !submitting && handleSelect(p)}
								style={{ opacity: submitting ? 0.5 : 1 }}
							>
								<img src={p.sprite_url || `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${p.id}.png`} alt={p.name} />
								<div className="nm">{p.name}</div>
								<div className="id">#{String(p.id).padStart(4, "0")}</div>
							</div>
						))}
						{options.length === 0 && search.length > 0 && (
							<div className="empty">No matches</div>
						)}
					</div>
				</div>
			</div>
		</div>
	);
}
