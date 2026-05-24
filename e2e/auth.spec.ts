import { test, expect } from "@playwright/test";
import { login, logout, ensureTestAccount, TEST_EMAIL, TEST_PASSWORD } from "./helpers";

test.describe("Authentication", () => {
  test.beforeAll(async () => {
    await ensureTestAccount();
  });

  test.describe("Login", () => {
    test("shows login form on initial load", async ({ page }) => {
      await page.goto("/");
      await expect(page.getByRole("button", { name: "Sign in →" })).toBeVisible();
      await expect(page.getByRole("textbox", { name: "you@example.com" })).toBeVisible();
      await expect(page.getByRole("textbox", { name: "••••••••" })).toBeVisible();
      await expect(page.getByText("Track your shiny journey")).toBeVisible();
    });

    test("shows both Sign in and Register tabs", async ({ page }) => {
      await page.goto("/");
      await expect(page.getByRole("button", { name: "Sign in", exact: true })).toBeVisible();
      await expect(page.getByRole("button", { name: "Register" })).toBeVisible();
    });

    test("fails with wrong credentials and shows error", async ({ page }) => {
      await page.goto("/");
      await page.getByRole("textbox", { name: "you@example.com" }).fill("nobody@nowhere.com");
      await page.getByRole("textbox", { name: "••••••••" }).fill("wrongpassword");
      await page.getByRole("textbox", { name: "••••••••" }).press("Enter");
      await expect(page.getByText(/invalid credentials/i)).toBeVisible();
      await expect(page.getByRole("button", { name: "Sign in →" })).toBeVisible();
    });

    test("fails with correct email but wrong password", async ({ page }) => {
      await page.goto("/");
      await page.getByRole("textbox", { name: "you@example.com" }).fill(TEST_EMAIL);
      await page.getByRole("textbox", { name: "••••••••" }).fill("WrongPassword!");
      await page.getByRole("textbox", { name: "••••••••" }).press("Enter");
      await expect(page.getByText(/invalid credentials/i)).toBeVisible();
    });

    test("succeeds with valid credentials and lands on Dashboard", async ({ page }) => {
      await page.goto("/");
      await page.getByRole("textbox", { name: "you@example.com" }).fill(TEST_EMAIL);
      await page.getByRole("textbox", { name: "••••••••" }).fill(TEST_PASSWORD);
      await page.getByRole("textbox", { name: "••••••••" }).press("Enter");
      await expect(page.getByRole("button", { name: "New Hunt", exact: true })).toBeVisible({ timeout: 10000 });
      // Heading is "Dashboard" or "No active hunts" depending on hunt count
      await expect(page.getByRole("heading", { name: /dashboard|no active hunts/i })).toBeVisible();
    });

    test("persists session across page reload", async ({ page }) => {
      await login(page);
      await page.reload();
      await expect(page.getByRole("button", { name: "New Hunt" })).toBeVisible();
    });
  });

  test.describe("Register", () => {
    test("shows register form when Register tab clicked", async ({ page }) => {
      await page.goto("/");
      await page.getByRole("button", { name: "Register" }).click();
      await expect(page.getByRole("textbox", { name: "trainer_name" })).toBeVisible();
      await expect(page.getByRole("button", { name: "Create account →" })).toBeVisible();
      await expect(page.getByText(/by registering/i)).toBeVisible();
    });

    test("fails with a duplicate email", async ({ page }) => {
      await page.goto("/");
      await page.getByRole("button", { name: "Register" }).click();
      await page.getByRole("textbox", { name: "trainer_name" }).fill("dup_user");
      await page.getByRole("textbox", { name: "you@example.com" }).fill(TEST_EMAIL);
      await page.getByRole("textbox", { name: "••••••••" }).fill("Password1!");
      await page.getByRole("textbox", { name: "••••••••" }).press("Enter");
      await expect(page.getByText(/invalid credentials|already/i)).toBeVisible();
    });

    test("succeeds with a new email and shows success message", async ({ page }) => {
      const unique = `test_${Date.now()}@example.com`;
      const uniqueUsername = `trainer_${Date.now()}`;
      await page.goto("/");
      await page.getByRole("button", { name: "Register" }).click();
      await page.getByRole("textbox", { name: "trainer_name" }).fill(uniqueUsername);
      await page.getByRole("textbox", { name: "you@example.com" }).fill(unique);
      await page.getByRole("textbox", { name: "••••••••" }).fill("Test1234!");
      // Click the submit button explicitly — more reliable than pressing Enter
      await page.getByRole("button", { name: /create account/i }).click();
      await expect(page.getByText(/registered|please sign in/i)).toBeVisible({ timeout: 15000 });
      await expect(page.getByRole("button", { name: "Sign in →" })).toBeVisible();
    });
  });

  test.describe("Logout", () => {
    test("logs out and returns to login screen", async ({ page }) => {
      await login(page);
      await logout(page);
      await expect(page.getByRole("button", { name: "Sign in →" })).toBeVisible();
    });

    test("clears session — reload shows login page after logout", async ({ page }) => {
      await login(page);
      await logout(page);
      await page.reload();
      await expect(page.getByRole("button", { name: "Sign in →" })).toBeVisible();
    });
  });
});
