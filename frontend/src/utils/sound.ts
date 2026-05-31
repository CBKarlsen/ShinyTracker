// ShinyTracker sound utilities — Web Audio API, no asset files.

const STORAGE_KEY = "st_sound_enabled";

let _ctx: AudioContext | null = null;

function getAudioContext(): AudioContext | null {
	try {
		if (!_ctx) {
			_ctx = new AudioContext();
		}
		return _ctx;
	} catch {
		return null;
	}
}

export function isSoundEnabled(): boolean {
	const stored = localStorage.getItem(STORAGE_KEY);
	// Default ENABLED — null means never set, treat as enabled.
	return stored !== "0";
}

export function setSoundEnabled(enabled: boolean): void {
	localStorage.setItem(STORAGE_KEY, enabled ? "1" : "0");
}

/**
 * Play a short two-note ascending chime (triangle wave, 660 Hz → 880 Hz).
 * Each note is ~150 ms with a smooth gain envelope to avoid clicks.
 * No-ops silently if sound is disabled or Web Audio is unavailable.
 */
export function playFoundItChime(): void {
	if (!isSoundEnabled()) return;

	try {
		const ctx = getAudioContext();
		if (!ctx) return;

		// Resume the context in case it was suspended (autoplay policy).
		const resume = ctx.state === "suspended" ? ctx.resume() : Promise.resolve();

		resume
			.then(() => {
				const now = ctx.currentTime;
				const noteLength = 0.15;
				const gap = 0.04;

				const playNote = (freq: number, startTime: number) => {
					const osc = ctx.createOscillator();
					const gain = ctx.createGain();

					osc.type = "triangle";
					osc.frequency.setValueAtTime(freq, startTime);

					// Smooth attack + decay envelope to avoid clicks.
					gain.gain.setValueAtTime(0, startTime);
					gain.gain.linearRampToValueAtTime(0.22, startTime + 0.02);
					gain.gain.exponentialRampToValueAtTime(0.001, startTime + noteLength);

					osc.connect(gain);
					gain.connect(ctx.destination);

					osc.start(startTime);
					osc.stop(startTime + noteLength);
				};

				playNote(660, now);
				playNote(880, now + noteLength + gap);
			})
			.catch(() => {
				// Silently swallow — never throw into the UI.
			});
	} catch {
		// Silently swallow any unexpected errors.
	}
}
