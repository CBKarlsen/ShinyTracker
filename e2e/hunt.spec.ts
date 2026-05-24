import { test, expect, type Page } from "@playwright/test";
import { login, ensureTestAccount, cleanupActiveHunts, cleanupUserGames } from "./helpers";

const API = "http://127.0.0.1:8080";

/** Add Sword/Shield to the test account via API — faster than driving the UI toggle. */
async function ensureSwShOwned(page: Page) {
  const token = await page.evaluate(() => localStorage.getItem("token"));
  const userId = await page.evaluate(() => localStorage.getItem("userId"));
  const gamesRes = await page.request.get(`${API}/api/games`);
  if (gamesRes.ok()) {
    const games: { id: number; title: string }[] = await gamesRes.json();
    const swsh = games.find(g => g.title.includes("Sword"));
    if (swsh) {
      await page.request.post(`${API}/api/user/${userId}/games/${swsh.id}`, {
        data: { has_shiny_charm: false },
        headers: { Authorization: `Bearer ${token}` },
        failOnStatusCode: false,
      });
    }
  }
}

test.describe("New Hunt Modal", () => {
  test.beforeAll(async () => {
    await ensureTestAccount();
  });

  test.beforeEach(async ({ page }) => {
    await login(page);
    await cleanupActiveHunts(page);
    await cleanupUserGames(page);
    await ensureSwShOwned(page);
    await page.reload();
    await expect(page.getByRole("button", { name: "New Hunt", exact: true })).toBeVisible({ timeout: 10000 });
  });

  test("opens via topbar New Hunt button", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Start a new hunt" })).toBeVisible();
    await expect(page.getByRole("textbox", { name: "Search any Pokémon…" })).toBeVisible();
  });

  test("opens via dashboard Start hunting button when no active hunts", async ({ page }) => {
    const startBtn = page.getByRole("button", { name: /start hunting/i });
    if (await startBtn.isVisible()) {
      await startBtn.click();
      await expect(page.getByRole("heading", { name: "Start a new hunt" })).toBeVisible();
    }
  });

  test("closes when scrim (backdrop) is clicked", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Start a new hunt" })).toBeVisible();
    await page.locator(".scrim").click({ position: { x: 10, y: 10 } });
    await expect(page.getByRole("heading", { name: "Start a new hunt" })).not.toBeVisible();
  });

  test("Pokémon search filters results", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("bulb");
    await expect(page.locator(".poke-search-results").getByText("bulbasaur")).toBeVisible();
    await expect(page.locator(".poke-search-results").getByText("ivysaur")).not.toBeVisible();
  });

  test("shows 'No matches' for gibberish search term", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("zzzznotareal");
    await expect(page.getByText("No matches")).toBeVisible();
  });

  test("step 2 shows pokemon header and Change button after selection", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    // exact:true — "Start hunting" button also contains "Hunting" as substring
    await expect(page.getByText("Hunting", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Change" })).toBeVisible();
  });

  test("Change button returns to Pokémon search step", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.getByRole("button", { name: "Change" }).click();
    await expect(page.getByRole("textbox", { name: "Search any Pokémon…" })).toBeVisible();
  });

  test("shows 'not available in your games' message for pikachu with SwSh owned", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("pikachu");
    await page.locator(".poke-search-results").getByText("pikachu").first().click();
    await expect(
      page.getByText(/isn't available in your games|haven't added any games/i)
    ).toBeVisible({ timeout: 5000 });
  });

  test("Go to Game Library CTA navigates and closes modal", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("pikachu");
    await page.locator(".poke-search-results").getByText("pikachu").first().click();
    const goBtn = page.getByRole("button", { name: /game library|manage games/i });
    if (await goBtn.isVisible({ timeout: 5000 })) {
      await goBtn.click();
      await expect(page.getByRole("heading", { name: "Game Library" })).toBeVisible();
      await expect(page.getByRole("heading", { name: "Start a new hunt" })).not.toBeVisible();
    }
  });

  test("Start hunt button is disabled until a method is selected", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.waitForTimeout(500);
    const startHuntBtn = page.getByRole("button", { name: "Start hunt", exact: true });
    await expect(startHuntBtn).toBeDisabled();
  });

  test("inline preview shows pokemon name, game, odds, and ETA when method is selected", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    // Scope to the modal drawer to avoid matching hunt cards on the dashboard
    await expect(page.locator(".drawer").getByText(/wooloo/i).first()).toBeVisible();
    await expect(page.getByText("Base odds")).toBeVisible();
    await expect(page.getByText("Live Odds")).toBeVisible();
    await expect(page.getByText("ETA expected")).toBeVisible();
    await expect(page.getByRole("button", { name: "Start hunt", exact: true })).toBeVisible();
  });
});

test.describe("Active Hunt — Dashboard", () => {
  let customMethodId: number | null = null;

  test.beforeAll(async () => {
    await ensureTestAccount();
  });

  test.beforeEach(async ({ page }) => {
    await login(page);
    await cleanupActiveHunts(page);
    await ensureSwShOwned(page);

    const token = await page.evaluate(() => localStorage.getItem("token"));
    
    // Find Wooloo
    const pokemonRes = await page.request.get(`${API}/api/pokemon?q=wooloo`);
    const pokemons = await pokemonRes.json();
    const wooloo = pokemons.find((p: any) => p.name.toLowerCase() === "wooloo");
    const woolooId = wooloo?.id;
    
    // Find Sword game
    const gamesRes = await page.request.get(`${API}/api/games`);
    const games = await gamesRes.json();
    const swsh = games.find((g: any) => g.title.includes("Sword"));
    const gameId = swsh?.id;

    if (woolooId && gameId && token) {
      // Create a custom Poké Radar Gen 4 method for Wooloo
      const methodRes = await page.request.post(`${API}/api/admin/hunt-methods`, {
        data: {
          pokemon_id: woolooId,
          game_id: gameId,
          method_name: "Test Poké Radar",
          base_rolls: 1,
          charm_rolls: 0,
          avg_time_seconds: 30,
          is_recommended: false,
          formula_type: "radar_chain_gen4"
        },
        headers: { Authorization: `Bearer ${token}` }
      });
      if (methodRes.ok()) {
        const methodData = await methodRes.json();
        customMethodId = methodData.id;
      }
    }

    // Reload so Dashboard re-fetches the now-empty hunt list (cleanup runs via API, no automatic re-render)
    await page.reload();
    await expect(page.getByRole("button", { name: "New Hunt", exact: true })).toBeVisible({ timeout: 10000 });
  });

  test.afterEach(async ({ page }) => {
    if (customMethodId) {
      const token = await page.evaluate(() => localStorage.getItem("token"));
      if (token) {
        await page.request.delete(`${API}/api/admin/hunt-methods/${customMethodId}`, {
          headers: { Authorization: `Bearer ${token}` }
        });
      }
      customMethodId = null;
    }
  });

  test("creating a hunt shows it on the dashboard", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    await expect(page.getByRole("button", { name: /\+1 encounter/ })).toBeVisible();
    // The hero tag says "Active Hunt · Pinned" — use first() to avoid matching "Active Hunts" stat label
    await expect(page.locator(".hero-tag").first()).toBeVisible();
  });

  test("+1 encounter button increments counter", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row", { hasText: "Test Poké Radar" }).first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // The encounter counter is in .hero-counter .num (fmtNum formats it as "0", "1", etc.)
    const counterEl = page.locator(".hero-counter .num");
    const before = Number((await counterEl.textContent())?.replace(/,/g, "") ?? "0");

    await page.getByRole("button", { name: /\+1 encounter/ }).click();
    await page.getByRole("button", { name: /\+1 encounter/ }).click();
    await page.waitForTimeout(2000); // wait for debounce

    const after = Number((await counterEl.textContent())?.replace(/,/g, "") ?? "0");
    expect(after).toBeGreaterThan(before);
  });

  test("SPACE key increments encounter counter", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row", { hasText: "Test Poké Radar" }).first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    const counterEl = page.locator(".hero-counter .num");
    await counterEl.waitFor({ state: "visible" });
    // React's window keydown handler re-registers in useEffect, which runs after browser paint.
    // A brief wait ensures the handler is live before dispatching Space.
    await page.waitForTimeout(500);

    const before = Number((await counterEl.textContent())?.replace(/,/g, "") ?? "0");

    await page.keyboard.press("Space");
    // localCounts updates immediately (optimistic) — wait for the DOM to reflect the change
    await expect(counterEl).not.toHaveText(String(before), { timeout: 3000 });
    // Then wait for the debounce PATCH to finish (1.5s) so we read the stable value
    await page.waitForTimeout(1700);

    const after = Number((await counterEl.textContent())?.replace(/,/g, "") ?? "0");
    expect(after).toBeGreaterThan(before);
  });

  test("SPACE key pressed multiple times rapidly increments counter correctly", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row", { hasText: "Test Poké Radar" }).first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    const counterEl = page.locator(".hero-counter .num");
    await counterEl.waitFor({ state: "visible" });
    await page.waitForTimeout(500);

    const before = Number((await counterEl.textContent())?.replace(/,/g, "") ?? "0");

    // Press Space 5 times rapidly
    for (let i = 0; i < 5; i++) {
      await page.keyboard.press("Space");
    }

    // Wait for the UI to update
    await expect(counterEl).toHaveText(String(before + 5), { timeout: 3000 });

    // Wait for the debounce PATCH to finish (1.5s) and verify it's persisted
    await page.waitForTimeout(1700);
    await page.reload();
    await expect(counterEl).toHaveText(String(before + 5), { timeout: 3000 });
  });

  test("Pause button pauses timer and shows Resume + reset", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // Wait for timer to accumulate > 0 seconds — "reset" button only appears when sessionSec > 0
    await page.waitForTimeout(1500);
    await page.getByRole("button", { name: "Pause" }).click();
    await expect(page.getByRole("button", { name: "Resume" })).toBeVisible();
    await expect(page.getByText(/paused/i)).toBeVisible();
    await expect(page.getByRole("button", { name: "reset" })).toBeVisible();
  });

  test("Resume button resumes a paused timer", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    await page.getByRole("button", { name: "Pause" }).click();
    await page.getByRole("button", { name: "Resume" }).click();
    await expect(page.getByRole("button", { name: "Pause" })).toBeVisible();
    await expect(page.getByText(/recording/i)).toBeVisible();
  });

  test("Log phase button is visible on active hunt", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // Scope to hero card — avoids matching the icon-only "Log phase" button in the compact list
    await expect(page.locator(".hero").getByRole("button", { name: "Log phase" }).first()).toBeVisible();
  });

  test("Found it! completes the hunt and removes it from dashboard", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // "Found it!" text button is only on the hero card; compact card has title="Found it" (no !)
    await page.getByRole("button", { name: "Found it!", exact: true }).click();
    await expect(page.getByRole("button", { name: "Found it!", exact: true })).not.toBeVisible({ timeout: 5000 });
  });

  test("completed hunt appears in Historic Hunts with SHINY tag", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();
    await page.getByRole("button", { name: "Found it!", exact: true }).click();

    await page.getByRole("button", { name: "Historic Hunts" }).click();
    await expect(page.getByRole("heading", { name: "Historic Hunts" })).toBeVisible();
    await expect(page.locator(".nm", { hasText: "wooloo" }).first()).toBeVisible();
    await expect(page.getByText("SHINY").first()).toBeVisible();
  });

  test("sidebar Dashboard badge shows active hunt count", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row").first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    await expect(page.getByRole("button", { name: /Dashboard \d+/ })).toBeVisible({ timeout: 3000 });
  });

  test("dynamic odds update as encounters increment", async ({ page }) => {
    const token = await page.evaluate(() => localStorage.getItem("token"));
    
    // Find Wooloo
    const pokemonRes = await page.request.get(`${API}/api/pokemon?q=wooloo`);
    expect(pokemonRes.ok()).toBe(true);
    const pokemons = await pokemonRes.json();
    const wooloo = pokemons.find((p: any) => p.name.toLowerCase() === "wooloo");
    expect(wooloo).toBeDefined();
    const woolooId = wooloo.id;

    // Open New Hunt modal and search for wooloo
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();

    // Select our custom Poké Radar method
    const radarRow = page.locator(".opt-row", { hasText: "Test Poké Radar" }).first();
    await radarRow.click();

    // Verify dynamic starting odds (1 / 65,536) in the drawer preview
    await expect(page.locator(".drawer").getByText("1 / 65,536")).toBeVisible();

    // Start hunt
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // Verify starting odds on the dashboard active hunt card
    await expect(page.getByRole("button", { name: /\+1 encounter/ })).toBeVisible();
    await expect(page.locator(".odds-curve-head .pct").getByText("1 / 65,536")).toBeVisible();

    // Fetch the newly created active hunt to patch its count to 40
    const activeHuntsRes = await page.request.get(`${API}/api/hunts`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(activeHuntsRes.ok()).toBe(true);
    const hunts = await activeHuntsRes.json();
    const activeHunt = hunts.find((h: any) => h.status === "active" && h.pokemon_id === woolooId);
    expect(activeHunt).toBeDefined();

    // PATCH the active hunt to 40 encounters
    const patchRes = await page.request.patch(`${API}/api/hunts/${activeHunt.id}`, {
      data: { encounter_count: 40, status: "active" },
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(patchRes.ok()).toBe(true);

    // Reload the page so the dashboard displays the updated count and recalculates the live odds
    await page.reload();
    await expect(page.locator(".odds-curve-head .pct").getByText("1 / 99")).toBeVisible({ timeout: 10000 });
  });

  test("chain-specific UI inputs are hidden when a static method is active", async ({ page }) => {
    // 1. Start a static hunt (Masuda Method)
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    
    const staticRow = page.locator(".opt-row", { hasText: "masuda-method" }).first();
    await staticRow.click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // Verify chain-modifier is hidden
    await expect(page.locator("[data-testid='chain-modifier']")).not.toBeVisible();

    // 2. Start a dynamic hunt (Test Poké Radar)
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    
    const radarRow = page.locator(".opt-row", { hasText: "Test Poké Radar" }).first();
    await radarRow.click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // Verify chain-modifier is shown
    await expect(page.locator("[data-testid='chain-modifier']")).toBeVisible();
  });

  test("clicking + New Target button switches dashboard to Configure New Hunt mode", async ({ page }) => {
    // 1. Start a hunt (Masuda Method)
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("wooloo");
    await page.locator(".poke-search-results").getByText("wooloo").first().click();
    await page.locator(".opt-row", { hasText: "masuda-method" }).first().click();
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();

    // Verify we are in tracking mode ("Active Hunt · Pinned" is shown)
    await expect(page.locator(".hero-tag").first()).toContainText("Active Hunt · Pinned");

    // 2. Click "+ New Target" button
    await page.getByRole("button", { name: "+ New Target", exact: true }).click();

    // Verify we are now in "Configure New Hunt" mode
    await expect(page.locator(".hero-tag").first()).toContainText("Configure New Hunt");

    // Check that the target search input is visible
    await expect(page.getByPlaceholder("Search target Pokémon…")).toBeVisible();
  });
});
