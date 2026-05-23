const { chromium } = require("@playwright/test");

async function run() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  // Listen to console logs
  page.on("console", (msg) => {
    console.log(`[BROWSER CONSOLE] ${msg.type()}: ${msg.text()}`);
  });

  // Listen to network requests/responses
  page.on("response", async (response) => {
    if (response.url().includes("/api/pokemon")) {
      console.log(`[NETWORK] URL: ${response.url()}`);
      console.log(`[NETWORK] Status: ${response.status()}`);
      try {
        const text = await response.text();
        console.log(`[NETWORK] Response (truncated): ${text.slice(0, 500)}`);
      } catch (e) {
        console.log(`[NETWORK] Failed to read response body: ${e}`);
      }
    }
  });

  console.log("Navigating to app...");
  await page.goto("http://localhost:5173/");

  // Log in
  console.log("Logging in...");
  await page.locator("input[type=\"email\"]").fill("test@example.com");
  await page.locator("input[type=\"password\"]").fill("password123");
  await page.locator("button[type=\"submit\"]").click();

  // Wait for dashboard to load
  await page.waitForURL("**/");
  console.log("On dashboard.");

  // Wait a bit
  await page.waitForTimeout(1000);

  // Click "+ New Target"
  console.log("Clicking + New Target...");
  await page.getByRole("button", { name: "+ New Target", exact: true }).click();

  // Wait a bit
  await page.waitForTimeout(500);

  // Focus search input
  console.log("Focusing search input...");
  await page.getByPlaceholder("Search target Pokémon…").focus();

  // Wait for dropdown to render and fetch to complete
  await page.waitForTimeout(1500);

  // Print HTML of the dropdown container
  const dropdownHTML = await page.locator(".poke-search-results").innerHTML().catch(() => "NOT FOUND");
  console.log(`Dropdown HTML:\n${dropdownHTML}`);

  await browser.close();
}

run().catch(console.error);
