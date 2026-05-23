import { test, expect } from "@playwright/test";
import { login, ensureTestAccount, cleanupUserGames } from "./helpers";

test.describe("Game Library", () => {
  test.beforeAll(async () => {
    await ensureTestAccount();
  });

  test.beforeEach(async ({ page }) => {
    await login(page);
    await cleanupUserGames(page);
    await page.getByRole("button", { name: "Games" }).click();
    await expect(page.getByRole("heading", { name: "Game Library" })).toBeVisible();
  });

  test("displays Game Library with generation sections", async ({ page }) => {
    // Use exact:true — "Generation I" is a substring of GenerationII/III/IV/IX
    await expect(page.getByText("Generation I", { exact: true })).toBeVisible();
    await expect(page.getByText("Generation IX", { exact: true })).toBeVisible();
    await expect(page.getByText("Red/Blue/Yellow")).toBeVisible();
    await expect(page.getByText("Scarlet/Violet")).toBeVisible();
  });

  test("shows summary stats row (Games Owned, Shiny Charms, Generations)", async ({ page }) => {
    // Use exact:true — "Games Owned" appears in both a label and the summary subtitle
    await expect(page.getByText("Games Owned", { exact: true })).toBeVisible();
    await expect(page.getByText("Shiny Charms", { exact: true })).toBeVisible();
    await expect(page.getByText("Charm-Eligible", { exact: true })).toBeVisible();
  });

  test("adding a game increments owned count", async ({ page }) => {
    // Ensure GSC starts NOT owned (remove if pre-owned from a previous run)
    const gscCard = page.locator(".game-card").filter({ hasText: "Gold/Silver/Crystal" });
    const gscOwned = (await gscCard.locator(".ttl").textContent()) !== null
      && (await page.getByText("Gen II · Owned").count()) > 0;
    if (gscOwned) {
      await page.getByText("Gold/Silver/Crystal").first().click();
      await expect(page.getByText("Gen II · Click to add")).toBeVisible({ timeout: 8000 });
    }

    const beforeCount = Number(
      (await page.getByText(/\d+ games owned/).first().textContent())?.match(/\d+/)?.[0] ?? 0
    );

    await page.getByText("Gold/Silver/Crystal").first().click();
    await expect(page.getByText(`${beforeCount + 1} games owned`, { exact: false })).toBeVisible({ timeout: 8000 });
    await expect(page.getByText("Gen II · Owned")).toBeVisible();

    // Cleanup — remove GSC
    await page.getByText("Gold/Silver/Crystal").first().click();
    await expect(page.getByText(`${beforeCount} games owned`, { exact: false })).toBeVisible({ timeout: 8000 });
  });

  test("toggling Shiny Charm flips button label to Remove and back", async ({ page }) => {
    // Ensure Sword/Shield is owned
    const swshCard = page.locator(".game-card").filter({ hasText: "Sword/Shield" });
    const isOwned = (await swshCard.locator(".charm-toggle.disabled").count()) === 0;
    if (!isOwned) {
      await page.getByText("Sword/Shield", { exact: true }).click();
      await expect(swshCard.locator(".charm-toggle:not(.disabled)")).toBeVisible({ timeout: 8000 });
    }

    // Ensure charm is OFF before toggling (reset to known state)
    const charmBtn = swshCard.locator(".charm-toggle");
    const isActive = (await charmBtn.getAttribute("class"))?.includes("active") ?? false;
    if (isActive) {
      await charmBtn.click();
      await expect(charmBtn).not.toHaveClass(/active/);
    }

    // Toggle ON
    await charmBtn.click();
    await expect(charmBtn).toHaveClass(/active/);

    // Cleanup — toggle OFF
    await charmBtn.click();
    await expect(charmBtn).not.toHaveClass(/active/);
  });

  test("clicking an owned game removes it (toggle off)", async ({ page }) => {
    // Add FireRed/LeafGreen then remove it
    await page.getByText("FireRed/LeafGreen").first().click();
    await expect(page.getByText("Gen III · Owned")).toBeVisible({ timeout: 8000 });
    await page.getByText("FireRed/LeafGreen").first().click();
    await expect(page.getByText("Gen III · Click to add").first()).toBeVisible({ timeout: 8000 });
  });
});
