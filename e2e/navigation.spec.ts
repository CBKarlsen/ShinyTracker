import { test, expect } from "@playwright/test";
import { login, ensureTestAccount, cleanupUserGames } from "./helpers";

test.describe("Navigation & All Pages", () => {
  test.beforeAll(async () => {
    await ensureTestAccount();
  });

  test.beforeEach(async ({ page }) => {
    await login(page);
    await cleanupUserGames(page);
  });

  test("sidebar renders all navigation items", async ({ page }) => {
    const sidebar = page.getByRole("complementary");
    await expect(sidebar.getByRole("button", { name: "Dashboard" })).toBeVisible();
    await expect(sidebar.getByRole("button", { name: "Historic Hunts" })).toBeVisible();
    await expect(sidebar.getByRole("button", { name: "Living Dex" })).toBeVisible();
    await expect(sidebar.getByRole("button", { name: "Games" })).toBeVisible();
    await expect(sidebar.getByRole("button", { name: "Stats" })).toBeVisible();
    await expect(sidebar.getByRole("button", { name: "Odds Calculator" })).toBeVisible();
    await expect(sidebar.getByRole("button", { name: "Method Library" })).toBeVisible();
  });

  test("Dashboard page loads with correct heading and breadcrumb", async ({ page }) => {
    await page.getByRole("button", { name: "Dashboard" }).click();
    // Heading is "Dashboard" (with hunts) or "No active hunts" (empty) — both are valid
    await expect(page.getByRole("heading", { name: /dashboard|no active hunts/i })).toBeVisible();
    // Breadcrumb is split across spans — check .crumb container contains "Dashboard"
    await expect(page.locator(".crumb")).toContainText("Dashboard");
  });

  test("Historic Hunts page loads", async ({ page }) => {
    await page.getByRole("button", { name: "Historic Hunts" }).click();
    await expect(page.getByRole("heading", { name: "Historic Hunts" })).toBeVisible();
    // Subtitle only renders when hunt count > 0; fall back to empty-state message
    await expect(
      page.getByText(/shinies caught/i).or(page.getByText(/no completed hunts/i))
    ).toBeVisible({ timeout: 8000 });
  });

  test("Living Dex page loads with filter controls", async ({ page }) => {
    await page.getByRole("button", { name: "Living Dex" }).click();
    await expect(page.getByRole("heading", { name: "Shiny Living Dex" })).toBeVisible();
    await expect(page.getByRole("button", { name: "all" })).toBeVisible();
    await expect(page.getByRole("button", { name: "owned" })).toBeVisible();
    await expect(page.getByRole("button", { name: "missing" })).toBeVisible();
    await expect(page.getByText(/of 1025 shinies/i)).toBeVisible({ timeout: 8000 });
  });

  test("Game Library page loads with generation sections and stats row", async ({ page }) => {
    await page.getByRole("button", { name: "Games" }).click();
    await expect(page.getByRole("heading", { name: "Game Library" })).toBeVisible();
    // exact:true — "Generation I" is a substring of II, III, IV, IX
    await expect(page.getByText("Generation I", { exact: true })).toBeVisible();
    await expect(page.getByText("Generation IX", { exact: true })).toBeVisible();
    await expect(page.getByText("Games Owned", { exact: true })).toBeVisible();
    await expect(page.getByText("Shiny Charms", { exact: true })).toBeVisible();
  });

  test("Stats page loads with lifetime stats", async ({ page }) => {
    await page.getByRole("button", { name: "Stats" }).click();
    await expect(page.getByRole("heading", { name: "Stats & Records" })).toBeVisible();
    const statsPage = page.locator("div.page").filter({ has: page.getByRole("heading", { name: "Stats & Records" }) });
    await expect(statsPage.getByText("Total Shinies")).toBeVisible();
    await expect(statsPage.getByText("Total Encounters")).toBeVisible();
    await expect(statsPage.getByText("Hunt Hours")).toBeVisible();
    await expect(statsPage.getByText("Avg per Shiny")).toBeVisible();
    await expect(statsPage.getByRole("heading", { name: "Records", exact: true })).toBeVisible();
  });

  test("Stats page shows encounter history chart (last 30 days)", async ({ page }) => {
    await page.getByRole("button", { name: "Stats" }).click();
    await expect(page.getByRole("heading", { name: /encounters.*last 30/i })).toBeVisible();
    await expect(page.getByText("Method Breakdown")).toBeVisible();
  });

  test("Odds Calculator page loads and requires game selection", async ({ page }) => {
    await page.getByRole("button", { name: "Odds Calculator" }).click();
    await expect(page.getByRole("heading", { name: "Odds Calculator" })).toBeVisible();
    await expect(page.getByText("Select a game and method to see odds")).toBeVisible();
    await expect(page.getByRole("combobox").first()).toBeVisible();
  });

  test("Odds Calculator computes results after game + method selection", async ({ page }) => {
    await page.getByRole("button", { name: "Odds Calculator" }).click();
    await page.getByRole("combobox").first().selectOption("Sword/Shield");
    await page.getByRole("combobox").nth(1).selectOption("Soft Reset");
    await expect(page.getByText("Results")).toBeVisible();
    await expect(page.getByText("1/4096")).toBeVisible();
    await expect(page.getByText("ETA (estimate)")).toBeVisible();
  });

  test("Odds Calculator Shiny Charm checkbox updates odds", async ({ page }) => {
    await page.getByRole("button", { name: "Odds Calculator" }).click();
    await page.getByRole("combobox").first().selectOption("Sword/Shield");
    await page.getByRole("combobox").nth(1).selectOption("Soft Reset");
    
    const oddsLabel = page.locator(".stat-tile").filter({ has: page.locator(".t-label", { hasText: /^Odds$/ }) });
    const oddsVal = oddsLabel.locator(".v");
    const oddsBefore = await oddsVal.textContent();
    
    // Check the Shiny Charm checkbox (calculates client-side, no API call is made)
    await page.getByRole("checkbox", { name: "Shiny Charm" }).check();
    
    // Verify that the odds value in UI updates (decreases denominator)
    await expect(oddsVal).not.toHaveText(oddsBefore || "", { timeout: 3000 });
    
    const oddsAfter = await oddsVal.textContent();
    expect(oddsBefore).not.toBe(oddsAfter);
  });

  test("Method Library page loads with game filter and method tables", async ({ page }) => {
    await page.getByRole("button", { name: "Method Library" }).click();
    await expect(page.getByRole("heading", { name: "Method Library" })).toBeVisible();
    await expect(page.getByText("Browse encounter methods")).toBeVisible();
    await expect(page.getByRole("combobox")).toBeVisible();
    await expect(page.getByRole("table").first()).toBeVisible();
  });

  test("Method Library game filter narrows displayed methods", async ({ page }) => {
    await page.getByRole("button", { name: "Method Library" }).click();
    const tablesBefore = await page.getByRole("table").count();
    await page.getByRole("combobox").selectOption("Sword/Shield");
    const tablesAfter = await page.getByRole("table").count();
    expect(tablesAfter).toBeLessThanOrEqual(tablesBefore);
    await expect(page.getByRole("heading", { name: "Sword/Shield" })).toBeVisible();
  });

  test("global search box is present on every page", async ({ page }) => {
    for (const navBtn of ["Dashboard", "Historic Hunts", "Living Dex", "Games", "Stats"]) {
      await page.getByRole("button", { name: navBtn }).click();
      await expect(
        page.getByRole("textbox", { name: "Search hunts, Pokémon…" })
      ).toBeVisible();
    }
  });
});
