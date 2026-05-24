import { test, expect, type Page } from "@playwright/test";
import { login, ensureTestAccount, cleanupActiveHunts, cleanupUserGames } from "./helpers";

const API = "http://127.0.0.1:8080";

async function ensureGamesOwned(page: Page) {
  const token = await page.evaluate(() => localStorage.getItem("token"));
  const userId = await page.evaluate(() => localStorage.getItem("userId"));
  const gamesRes = await page.request.get(`${API}/api/games`);
  if (gamesRes.ok()) {
    const games: { id: number; title: string }[] = await gamesRes.json();
    const gameTitles = ["Ruby/Sapphire/Emerald", "Scarlet/Violet", "X/Y"];
    for (const title of gameTitles) {
      const g = games.find(x => x.title.includes(title) || title.includes(x.title));
      if (g) {
        await page.request.post(`${API}/api/user/${userId}/games/${g.id}`, {
          data: { has_shiny_charm: false },
          headers: { Authorization: `Bearer ${token}` },
          failOnStatusCode: false,
        });
      }
    }
  }
}

test.describe("Hunt Method Improvements", () => {
  test.beforeAll(async () => {
    await ensureTestAccount();
  });

  test.beforeEach(async ({ page }) => {
    await login(page);
    await cleanupActiveHunts(page);
    await cleanupUserGames(page);
    await ensureGamesOwned(page);
    await page.reload();
  });

  test("Mewtwo shows no breeding methods", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("mewtwo");
    await page.locator(".poke-search-results").getByText("mewtwo").first().click();

    // The search results/available methods should not contain "Breeding" or "masuda-method"
    // Wait for the modal or loader to finish
    await page.waitForTimeout(500);
    const options = page.locator(".opt-row");
    const count = await options.count();
    for (let i = 0; i < count; i++) {
      const text = await options.nth(i).innerText();
      expect(text.toLowerCase()).not.toContain("breeding");
      expect(text.toLowerCase()).not.toContain("masuda-method");
    }
  });

  test("Magikarp shows Breeding in Gen 3 and Masuda Method in Gen 9", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("magikarp");
    await page.locator(".poke-search-results").getByText("magikarp").first().click();

    await page.waitForTimeout(500);

    // Verify Breeding exists for Ruby/Sapphire/Emerald
    const breedingRow = page.locator(".opt-row", { hasText: "Ruby/Sapphire/Emerald" }).filter({ hasText: "Breeding" });
    await expect(breedingRow).toBeVisible();

    // Verify masuda-method exists for Scarlet/Violet
    const masudaRow = page.locator(".opt-row", { hasText: "Scarlet/Violet" }).filter({ hasText: "masuda-method" });
    await expect(masudaRow).toBeVisible();
  });

  test("Relicanth Gen 6 Chain Fishing odds scale correctly", async ({ page }) => {
    await page.getByRole("button", { name: "New Hunt", exact: true }).click();
    await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill("relicanth");
    await page.locator(".poke-search-results").getByText("relicanth").first().click();

    await page.waitForTimeout(500);

    // Select Chain Fishing in X/Y
    const fishingRow = page.locator(".opt-row", { hasText: "X/Y" }).filter({ hasText: "Chain Fishing" }).first();
    await expect(fishingRow).toBeVisible();
    await fishingRow.click();

    // Verify starting odds are 1/4,096
    await expect(page.locator(".drawer").getByText("1 / 4,096").first()).toBeVisible();

    // Start the hunt
    await page.getByRole("button", { name: "Start hunt", exact: true }).click();
    await expect(page.getByRole("button", { name: /\+1 encounter/ })).toBeVisible();

    // Go to Odds Calculator
    await page.getByRole("button", { name: "Odds Calculator" }).first().click();
    await expect(page.getByRole("heading", { name: "Odds Calculator" })).toBeVisible();

    // Select game and method
    await page.getByRole("combobox").first().selectOption("X/Y");
    await page.getByRole("combobox").nth(1).selectOption("Chain Fishing");

    // Chain Hooks label should be visible
    await expect(page.getByText("Chain Hooks")).toBeVisible();

    // The range input should be present. Set chain hooks to 20
    const slider = page.locator(".calc-layout input[type='range']");
    await expect(slider).toBeVisible();
    await slider.fill("20");

    // The counter value should display 20
    await expect(page.locator(".t-mono").getByText("20")).toBeVisible();

    // The calculated odds at chain 20 should display 1/99 (41 rolls)
    await expect(page.getByText("1/99")).toBeVisible();
  });
});
