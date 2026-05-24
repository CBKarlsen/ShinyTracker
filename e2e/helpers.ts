import { type Page, request as pwRequest, expect } from "@playwright/test";

export const TEST_EMAIL = "pw_suite@test.com";
export const TEST_PASSWORD = "Test1234!";
export const TEST_USERNAME = "pw_suite";
// Use 127.0.0.1 explicitly — Node 18+ resolves "localhost" to ::1 (IPv6)
// but the Go backend only listens on 127.0.0.1 (IPv4). Chromium handles
// the fallback, but pwRequest.newContext() (Node.js) does not.
const API = "http://127.0.0.1:8080";

/**
 * Ensure the shared test account exists. Safe to call repeatedly — duplicate
 * registration is silently ignored. Call once from test.beforeAll.
 */
export async function ensureTestAccount() {
  const ctx = await pwRequest.newContext({ baseURL: API });
  await ctx.post("/api/auth/register", {
    data: { username: TEST_USERNAME, email: TEST_EMAIL, password: TEST_PASSWORD },
    failOnStatusCode: false,
  });
  await ctx.dispose();
}

/**
 * API-based login: POSTs credentials directly, injects the JWT into
 * localStorage, then reloads so React picks up the authenticated state.
 * Much faster and more reliable than driving the UI login form.
 */
export async function login(page: Page, email = TEST_EMAIL, password = TEST_PASSWORD) {
  const res = await page.request.post(`${API}/api/auth/login`, {
    data: { email, password },
  });
  if (!res.ok()) {
    throw new Error(`Login API failed (${res.status()}): ${await res.text()}`);
  }
  const { token, user } = await res.json();

  await page.goto("/");
  await page.evaluate(
    ({ t, u }) => {
      localStorage.setItem("token", t);
      localStorage.setItem("userId", u);
    },
    { t: token, u: user.id },
  );
  await page.reload();
  // exact:true — "New hunt" (lowercase h) also exists in the empty dashboard state
  await expect(page.getByRole("button", { name: "New Hunt", exact: true })).toBeVisible({ timeout: 10000 });
}

export async function logout(page: Page) {
  await page.getByRole("button", { name: "Log out" }).click();
  await expect(page.getByRole("button", { name: "Sign in →" })).toBeVisible();
}

/**
 * Removes all owned games for the test user to start from a clean slate.
 * Must be called after login() so the auth token and userId are in localStorage.
 */
export async function cleanupUserGames(page: Page) {
  const token = await page.evaluate(() => localStorage.getItem("token"));
  const userId = await page.evaluate(() => localStorage.getItem("userId"));
  if (!token || !userId) return;

  const gamesRes = await page.request.get(`${API}/api/user/${userId}/games`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!gamesRes.ok()) return;

  const userGames = await gamesRes.json();
  const gamesList = Array.isArray(userGames) ? userGames : [];
  for (const ug of gamesList) {
    await page.request.delete(`${API}/api/user/${userId}/games/${ug.game_id}`, {
      headers: { Authorization: `Bearer ${token}` },
      failOnStatusCode: false,
    });
  }
}

/**
 * Completes all active hunts via the API so each test starts from a clean slate.
 * Must be called after login() so the auth token is in localStorage.
 */
export async function cleanupActiveHunts(page: Page) {
  const token = await page.evaluate(() => localStorage.getItem("token"));
  const huntsRes = await page.request.get(`${API}/api/hunts`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!huntsRes.ok()) return;
  const hunts: { id: string; status: string }[] = await huntsRes.json();
  const huntsList = Array.isArray(hunts) ? hunts : [];
  for (const h of huntsList.filter((h) => h.status === "active")) {
    await page.request.patch(`${API}/api/hunts/${h.id}`, {
      data: { encounter_count: 0, status: "completed" },
      headers: { Authorization: `Bearer ${token}` },
      failOnStatusCode: false,
    });
  }
}

/** Opens New Hunt modal, searches pokemon, picks first method, confirms. */
export async function createHunt(page: Page, pokemonName: string) {
  await page.getByRole("button", { name: "Dashboard" }).click();
  await page.getByRole("button", { name: "New Hunt", exact: true }).click();
  await page.getByRole("textbox", { name: "Search any Pokémon…" }).fill(pokemonName);
  await page.locator(".poke-search-results").getByText(pokemonName, { exact: false }).first().click();
  await page.locator(".opt-row").first().click();
  await page.getByRole("button", { name: "Configure →" }).click();
  await page.getByRole("button", { name: "Start hunt", exact: true }).click();
  await expect(page.getByRole("button", { name: /\+1 encounter/ })).toBeVisible();
}
