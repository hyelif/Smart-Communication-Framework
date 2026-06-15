import { chromium } from 'playwright';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

const SCREENSHOT_DIR = join(process.cwd(), 'screenshots');
mkdirSync(SCREENSHOT_DIR, { recursive: true });

const CONSOLE_LOG = join(SCREENSHOT_DIR, 'console-errors.txt');
const allConsoleErrors = [];

async function run() {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();

  // Collect console messages
  page.on('console', msg => {
    const type = msg.type();
    const text = msg.text();
    if (type === 'error' || type === 'warning') {
      allConsoleErrors.push(`[${type.toUpperCase()}] ${text}`);
    }
  });

  page.on('pageerror', err => {
    allConsoleErrors.push(`[PAGE_ERROR] ${err.message}`);
  });

  page.on('response', response => {
    if (response.status() >= 400) {
      allConsoleErrors.push(`[HTTP ${response.status()}] ${response.url()}`);
    }
  });

  try {
    // ─── Navigate to Dashboard ───
    console.log('Navigating to http://127.0.0.1:8000...');
    await page.goto('http://127.0.0.1:8000', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(2000); // Let animations settle

    // ─── Screenshot 1: Overview tab ───
    console.log('Taking screenshot: Overview tab');
    await page.screenshot({
      path: join(SCREENSHOT_DIR, '01-overview.png'),
      fullPage: true,
    });

    // ─── Screenshot 2: Communication tab ───
    console.log('Taking screenshot: Communication tab');
    const commTab = page.locator('button[role="tab"]', { hasText: 'Communication' });
    if (await commTab.isVisible()) {
      await commTab.click();
      await page.waitForTimeout(2000); // Let chart render
      await page.screenshot({
        path: join(SCREENSHOT_DIR, '02-communication.png'),
        fullPage: true,
      });
    } else {
      console.log('Communication tab not found');
    }

    // ─── Screenshot 3: Analytics tab ───
    console.log('Taking screenshot: Analytics tab');
    const analyticsTab = page.locator('button[role="tab"]', { hasText: 'Analytics' });
    if (await analyticsTab.isVisible()) {
      await analyticsTab.click();
      await page.waitForTimeout(2000);
      await page.screenshot({
        path: join(SCREENSHOT_DIR, '03-analytics.png'),
        fullPage: true,
      });
    } else {
      console.log('Analytics tab not found');
    }

    // ─── Screenshot 4: Nodes tab (sidebar) ───
    console.log('Taking screenshot: Nodes tab');
    const sidebar = page.locator('aside[role="navigation"]');
    const nodesLink = sidebar.locator('a', { hasText: 'Nodes' }).first();
    if (await nodesLink.isVisible()) {
      await nodesLink.click();
      await page.waitForTimeout(2000);
      await page.screenshot({
        path: join(SCREENSHOT_DIR, '04-nodes.png'),
        fullPage: true,
      });
    } else {
      console.log('Nodes link not found in sidebar');
    }

    // ─── Screenshot 5: Alerts tab (sidebar) ───
    console.log('Taking screenshot: Alerts tab');
    const alertsLink = sidebar.locator('a', { hasText: 'Alerts' }).first();
    if (await alertsLink.isVisible()) {
      await alertsLink.click();
      await page.waitForTimeout(2000);
      await page.screenshot({
        path: join(SCREENSHOT_DIR, '05-alerts.png'),
        fullPage: true,
      });
    } else {
      console.log('Alerts link not found in sidebar');
    }

  } catch (err) {
    allConsoleErrors.push(`[SCRIPT_ERROR] ${err.message}`);
    console.error('Error during screenshot capture:', err);
  } finally {
    // Write console errors to file
    writeFileSync(CONSOLE_LOG, allConsoleErrors.join('\n'), 'utf-8');
    console.log(`\nConsole errors written to: ${CONSOLE_LOG}`);
    console.log(`Total issues found: ${allConsoleErrors.length}`);

    await browser.close();
  }
}

run().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
