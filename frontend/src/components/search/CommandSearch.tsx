import { useEffect, useRef, useState } from "react";
import { usePokemonSearch } from "../../hooks/usePokemonSearch";
import type { Pokemon } from "../../types/models";

interface Props {
	open: boolean;
	onClose: () => void;
	onStartHunt: (pokemon: Pokemon) => void;
	onViewInDex: (pokemon: Pokemon) => void;
}

export default function CommandSearch({
	open,
	onClose,
	onStartHunt,
	onViewInDex,
}: Props) {
	const [query, setQuery] = useState("");
	const [highlight, setHighlight] = useState(0);
	const inputRef = useRef<HTMLInputElement>(null);
	const { results, loading } = usePokemonSearch(query);

	// Reset state and focus the input each time the palette opens.
	useEffect(() => {
		if (open) {
			setQuery("");
			setHighlight(0);
			// focus after paint so the element exists
			requestAnimationFrame(() => inputRef.current?.focus());
		}
	}, [open]);

	// Keep the highlighted index in range as results change.
	useEffect(() => {
		setHighlight((h) =>
			results.length === 0 ? 0 : Math.min(h, results.length - 1),
		);
	}, [results]);

	// Lock body scroll while open.
	useEffect(() => {
		if (!open) return;
		const prev = document.body.style.overflow;
		document.body.style.overflow = "hidden";
		return () => {
			document.body.style.overflow = prev;
		};
	}, [open]);

	if (!open) return null;

	const handleKeyDown = (e: React.KeyboardEvent) => {
		if (e.key === "Escape") {
			e.preventDefault();
			onClose();
		} else if (e.key === "ArrowDown") {
			e.preventDefault();
			if (results.length) setHighlight((h) => (h + 1) % results.length);
		} else if (e.key === "ArrowUp") {
			e.preventDefault();
			if (results.length)
				setHighlight((h) => (h - 1 + results.length) % results.length);
		} else if (e.key === "Enter") {
			e.preventDefault();
			const p = results[highlight];
			if (p) onStartHunt(p);
		}
	};

	return (
		<div className="cmd-scrim" onClick={onClose}>
			<div
				className="cmd-panel"
				role="dialog"
				aria-modal="true"
				aria-label="Search Pokémon"
				onClick={(e) => e.stopPropagation()}
				onKeyDown={handleKeyDown}
			>
				<div className="cmd-input-row">
					<svg
						viewBox="0 0 16 16"
						width="16"
						height="16"
						fill="none"
						stroke="currentColor"
						strokeWidth="1.5"
						aria-hidden="true"
					>
						<circle cx="7" cy="7" r="4.5" />
						<path d="M11 11l3 3" />
					</svg>
					<input
						ref={inputRef}
						className="cmd-input"
						placeholder="Search any Pokémon…"
						value={query}
						onChange={(e) => setQuery(e.target.value)}
					/>
				</div>

				<div className="cmd-results">
					{loading && query.trim() && (
						<div className="cmd-state">Searching…</div>
					)}
					{!loading && query.trim() && results.length === 0 && (
						<div className="cmd-state">No Pokémon found</div>
					)}
					{!query.trim() && (
						<div className="cmd-state">Type to search any Pokémon</div>
					)}
					{results.map((p, i) => (
						<div
							key={p.id}
							className={`cmd-row${i === highlight ? " active" : ""}`}
							onMouseEnter={() => setHighlight(i)}
							onClick={() => onStartHunt(p)}
						>
							<img src={p.sprite_url} alt="" width={28} height={28} />
							<span className="cmd-nm">{p.name}</span>
							<span className="cmd-id">#{String(p.id).padStart(4, "0")}</span>
							<button
								type="button"
								className="cmd-dex-btn"
								onClick={(e) => {
									e.stopPropagation();
									onViewInDex(p);
								}}
							>
								View in Dex
							</button>
						</div>
					))}
				</div>

				<div className="cmd-foot">
					<span>↑↓ move</span>
					<span>↵ start hunt</span>
					<span>esc close</span>
				</div>
			</div>
		</div>
	);
}
