// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');

const TUI_URL = 'file://' + path.resolve(__dirname, 'out/claude-tui.html');

test.describe('TUI Demo Engine — Dogfood', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(TUI_URL);
    await page.waitForTimeout(500);
  });

  // ── Smoke: page loads and renders ────────────────────────────────────────────
  test('renders window chrome', async ({ page }) => {
    await expect(page.locator('.window')).toBeVisible();
    await expect(page.locator('.title-bar')).toBeVisible();
    await expect(page.locator('.cc-header')).toBeVisible();
    await expect(page.locator('.status-bar')).toBeVisible();
  });

  test('populates shell identity from config', async ({ page }) => {
    await expect(page.locator('#cc-name')).toHaveText('Lossless Claude');
    await expect(page.locator('#cc-version')).toHaveText('v2.0.0');
    const pathEl = page.locator('#cc-path');
    await expect(pathEl).toHaveText('claude plugin install xgh@extreme-go-horse');
    await expect(pathEl).toHaveAttribute('href', '#install');
  });

  test('picks a random model string', async ({ page }) => {
    const model = await page.locator('#cc-model').textContent();
    const expected = ['medium effort', 'high effort', 'max effort', 'low effort', 'xhigh effort'];
    expect(expected).toContain(model.trim());
  });

  test('status bar shows left text', async ({ page }) => {
    await expect(page.locator('#status-left')).toHaveText('? for shortcuts · hold Space to speak');
  });

  // ── CSS variables applied ────────────────────────────────────────────────────
  test('CSS variables are applied from theme', async ({ page }) => {
    const bg = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--bg').trim()
    );
    expect(bg).toBe('#0d0e17');
  });

  // ── Demo autoplay starts ────────────────────────────────────────────────────
  test('demo autoplay starts and types a command', async ({ page }) => {
    // Wait for typing to begin (the first demo types /xgh-brief)
    await page.waitForFunction(() => {
      const input = document.getElementById('input-text');
      return input && input.textContent.length > 0;
    }, { timeout: 5000 });
    const text = await page.locator('#input-text').textContent();
    expect(text.length).toBeGreaterThan(0);
  });

  // ── Interactive mode: click to focus ─────────────────────────────────────────
  test('click on input row enters interactive mode', async ({ page }) => {
    // Wait for autoplay to start, then click to interrupt
    await page.waitForTimeout(1000);
    await page.locator('#input-row').click();
    await page.waitForTimeout(300);
    // Cursor should become visible
    await expect(page.locator('#cursor')).toBeVisible();
  });

  // ── Interactive mode: type anywhere ──────────────────────────────────────────
  test('typing anywhere enters interactive mode and seeds first char', async ({ page }) => {
    // Wait for autoplay to start, then type to interrupt
    await page.waitForTimeout(1000);
    await page.keyboard.press('h');
    await page.waitForTimeout(500);
    const text = await page.locator('#input-text').textContent();
    expect(text).toContain('h');
    await expect(page.locator('#cursor')).toBeVisible();
  });

  // ── Autocomplete ─────────────────────────────────────────────────────────────
  test('typing / shows autocomplete with commands', async ({ page }) => {
    await page.keyboard.press('/');
    await page.waitForTimeout(300);
    const ac = page.locator('#autocomplete');
    await expect(ac).toHaveClass(/visible/);
    // Should have rows for known commands
    const rows = ac.locator('.ac-row');
    const count = await rows.count();
    expect(count).toBeGreaterThan(0);
  });

  test('autocomplete filters as user types', async ({ page }) => {
    await page.keyboard.type('/ins', { delay: 50 });
    await page.waitForTimeout(200);
    const rows = page.locator('#autocomplete .ac-row');
    const count = await rows.count();
    expect(count).toBeGreaterThanOrEqual(1);
    const firstCmd = await rows.first().locator('.ac-cmd').textContent();
    expect(firstCmd).toContain('/install');
  });

  // ── Command execution: /help ─────────────────────────────────────────────────
  test('/help lists all commands', async ({ page }) => {
    await page.keyboard.type('/help', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('/install');
    expect(text).toContain('/about');
    expect(text).toContain('/color');
    expect(text).toContain('/help');
  });

  // ── Command execution: /install ──────────────────────────────────────────────
  test('/install shows install instructions', async ({ page }) => {
    await page.keyboard.type('/install', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('Install xgh');
    expect(text).toContain('claude plugin install');
  });

  // ── Command execution: /about ────────────────────────────────────────────────
  test('/about shows about info', async ({ page }) => {
    await page.keyboard.type('/about', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('xgh');
  });

  // ── Command execution: /color ────────────────────────────────────────────────
  test('/color changes accent and shows confirmation', async ({ page }) => {
    await page.keyboard.type('/color pink', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('pink');
  });

  // ── Command execution: /rename ───────────────────────────────────────────────
  test('/rename updates divider label', async ({ page }) => {
    await page.keyboard.type('/rename my-label', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const label = await page.locator('#input-label').textContent();
    expect(label).toContain('my-label');
  });

  // ── Unknown command ──────────────────────────────────────────────────────────
  test('unknown command shows error message', async ({ page }) => {
    await page.keyboard.type('/nonexistent', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('Unknown command');
    expect(text).toContain('/help');
  });

  // ── ESC exits interactive mode ───────────────────────────────────────────────
  test('Escape exits interactive mode', async ({ page }) => {
    // Wait for autoplay to start, then enter interactive
    await page.waitForTimeout(1000);
    await page.keyboard.press('h');
    await page.waitForTimeout(500);
    await expect(page.locator('#cursor')).toBeVisible();

    // Exit
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    await expect(page.locator('#cursor')).toBeHidden();
  });

  // ── Race condition: ESC + immediate re-entry ─────────────────────────────────
  test('ESC then immediate re-entry does not restart autoplay', async ({ page }) => {
    // Wait for autoplay to start, then enter interactive
    await page.waitForTimeout(1000);
    await page.keyboard.press('h');
    await page.waitForTimeout(500);

    // Exit
    await page.keyboard.press('Escape');
    await page.waitForTimeout(100);

    // Immediately re-enter
    await page.keyboard.press('x');
    await page.waitForTimeout(100);

    // Should still be in interactive mode, cursor visible
    await expect(page.locator('#cursor')).toBeVisible();
    const text = await page.locator('#input-text').textContent();
    expect(text).toContain('x');

    // Wait past the 600ms debounce
    await page.waitForTimeout(700);

    // Should STILL be interactive — autoplay should NOT have fired
    await expect(page.locator('#cursor')).toBeVisible();
  });

  // ── Demo scene renders tool blocks ───────────────────────────────────────────
  test('demo scene renders skill badges and tool blocks', async ({ page }) => {
    // Let the first demo play for a few seconds
    await page.waitForTimeout(4000);
    const conv = page.locator('#conv');
    // Should have at least one skill badge
    const badges = conv.locator('.skill-badge');
    await expect(badges.first()).toBeVisible({ timeout: 8000 });
    // Should have at least one tool block
    const tools = conv.locator('.tool-block');
    await expect(tools.first()).toBeVisible({ timeout: 3000 });
  });

  // ── Screenshot: full autoplay cycle ──────────────────────────────────────────
  test('screenshot: demo in progress', async ({ page }) => {
    await page.waitForTimeout(6000);
    await page.screenshot({ path: 'src/site/tui/out/screenshot-demo.png', fullPage: true });
  });

  test('screenshot: interactive /help', async ({ page }) => {
    await page.keyboard.type('/help', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    await page.screenshot({ path: 'src/site/tui/out/screenshot-help.png', fullPage: true });
  });

  test('screenshot: autocomplete', async ({ page }) => {
    await page.keyboard.type('/co', { delay: 50 });
    await page.waitForTimeout(300);
    await page.screenshot({ path: 'src/site/tui/out/screenshot-autocomplete.png', fullPage: true });
  });
});
