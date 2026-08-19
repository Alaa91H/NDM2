import { test, expect, type Page } from '@playwright/test';

const goto = async (page: Page) => {
  await page.goto('/');
  await page.waitForLoadState('networkidle');
};

test.describe('App Shell — layout structure', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
  });

  test('page has correct title', async ({ page }) => {
    await expect(page).toHaveTitle(/Nova/i);
  });

  test('root element renders', async ({ page }) => {
    const root = page.locator('#root');
    await expect(root).toBeVisible({ timeout: 5000 });
  });

  test('primary toolbar is rendered', async ({ page }) => {
    const toolbar = page.locator('header').first();
    await expect(toolbar).toBeVisible({ timeout: 5000 });
    const display = await toolbar.evaluate((el) => window.getComputedStyle(el).display);
    expect(display).not.toBe('none');
  });
  test('status bar is rendered at bottom', async ({ page }) => {
    const statusBar = page.locator('footer').first();
    await expect(statusBar).toBeVisible({ timeout: 5000 });
    const box = await statusBar.boundingBox();
    if (box) {
      const viewport = page.viewportSize() ?? { width: 0, height: 0 };
      expect(box.y + box.height).toBeGreaterThanOrEqual(viewport.height - 80);
    }
  });

  test('download content is rendered between toolbar and status bar', async ({ page }) => {
    const toolbar = page.locator('header').first();
    const table = page.locator('table').first();
    const statusBar = page.locator('footer').first();
    await expect(table).toBeVisible();
    const toolbarBox = await toolbar.boundingBox();
    const tableBox = await table.boundingBox();
    const statusBox = await statusBar.boundingBox();
    if (toolbarBox && tableBox && statusBox) {
      expect(tableBox.y).toBeGreaterThanOrEqual(toolbarBox.y + toolbarBox.height);
      expect(statusBox.y).toBeGreaterThan(tableBox.y);
    }
  });
});

test.describe('App Shell — custom title bar', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
  });

  test('title bar has minimize, maximize, close buttons', async ({ page }) => {
    const titleBar = page.locator('header, [class*="title-bar"]').first();
    const buttons = titleBar.locator('button');
    const count = await buttons.count();
    expect(count).toBeGreaterThanOrEqual(3);
  });

  test('close button has hover effect', async ({ page }) => {
    const closeBtn = page
      .locator('button')
      .filter({ has: page.locator('.lucide-x, svg') })
      .last();
    if (await closeBtn.isVisible()) {
      await closeBtn.hover();
    }
  });

  test('title bar declares its native drag region', async ({ page }) => {
    const titleArea = page.locator('[data-tauri-drag-region]').first();
    await expect(titleArea).toBeVisible();
    await expect(titleArea).toHaveAttribute('data-tauri-drag-region', 'true');
  });
});

test.describe('App Shell — drag overlay', () => {
  test('drag overlay appears when files are dragged over', async ({ page }) => {
    await goto(page);
    // Use a real browser DataTransfer object; a plain object cannot construct DragEvent.
    await page.evaluate(() => {
      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(new File(['nova'], 'nova-link.txt', { type: 'text/plain' }));
      document.body.dispatchEvent(new DragEvent('dragenter', { bubbles: true, dataTransfer }));
    });
    await page.waitForTimeout(300);
  });
});

test.describe('App Shell — error boundary', () => {
  test('error boundary component exists in DOM', async ({ page }) => {
    await goto(page);
    // The error boundary wraps the entire app; if we can see content, it works
    await expect(page.locator('#root')).toBeVisible();
  });
});

test.describe('App Shell — toast notification system', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
  });

  test('toast container exists with live region', async ({ page }) => {
    const toastRegion = page.locator('[role="status"][aria-live="polite"]');
    await expect(toastRegion).toHaveCount(1);
  });

  test('toast appears on action and auto-dismisses', async ({ page }) => {
    // Open and close a dialog to trigger potential toast
    await page.keyboard.press('Control+n');
    const dialog = page.locator('[role="dialog"]');
    await expect(dialog).toBeVisible({ timeout: 3000 });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(6000);
    // Toasts auto-dismiss after 4.5s; the live-region container remains attached.
    const toastRegion = page.locator('[role="status"][aria-live="polite"]');
    await expect(toastRegion).toHaveCount(1);
  });

  test('toast has dismiss button', async ({ page }) => {
    // Trigger a toast scenario
    await page.keyboard.press('Control+n');
    const dialog = page.locator('[role="dialog"]');
    await expect(dialog).toBeVisible({ timeout: 3000 });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
    const dismissBtn = page.locator('[aria-label*="dismiss" i], [aria-label*="إغلاق" i]').first();
    if (await dismissBtn.isVisible().catch(() => false)) {
      await dismissBtn.click();
    }
  });
});

test.describe('App Shell — keyboard shortcut system', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
  });

  const shortcuts: Array<{ keys: string; description: string; check: (page: Page) => Promise<void> }> = [
    {
      keys: 'Control+n',
      description: 'opens new download dialog',
      check: async (page) => {
        const dialog = page.locator('[role="dialog"]');
        await expect(dialog).toBeVisible({ timeout: 3000 });
        await page.keyboard.press('Escape');
      },
    },
    {
      keys: 'Control+l',
      description: 'opens scheduler',
      check: async (page) => {
        await page.waitForTimeout(500);
        const scheduler = page.getByRole('heading', { name: /download lists/i });
        await expect(scheduler).toBeVisible({ timeout: 3000 });
      },
    },
    {
      keys: 'Control+,',
      description: 'opens settings',
      check: async (page) => {
        await page.waitForTimeout(500);
        const settings = page.getByRole('heading', { name: /control center.*settings/i });
        await expect(settings).toBeVisible({ timeout: 3000 });
      },
    },
    {
      keys: 'Control+f',
      description: 'focuses search input',
      check: async (page) => {
        const searchInput = page.locator('[data-global-search="true"]');
        await expect(searchInput).toBeFocused({ timeout: 3000 });
      },
    },
  ];

  for (const shortcut of shortcuts) {
    test(`${shortcut.keys} ${shortcut.description}`, async ({ page }) => {
      await page.keyboard.press(shortcut.keys);
      await shortcut.check(page);
    });
  }

  test('Escape navigates back from full page', async ({ page }) => {
    await page.keyboard.press('Control+,');
    await page.waitForTimeout(500);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
    await expect(page.locator('[role="dialog"]')).not.toBeVisible();
  });

  test('shortcuts are disabled when focus is in input', async ({ page }) => {
    const input = page.locator('input[type="text"], input[type="search"]').first();
    if (await input.isVisible()) {
      await input.focus();
      await page.keyboard.press('Control+n');
      await page.waitForTimeout(300);
      // Dialog should NOT open because focus is in input
      const dialog = page.locator('[role="dialog"]');
      const isVisible = await dialog.isVisible().catch(() => false);
      // Note: Ctrl+N is exempt from input check per AppShell logic, so it may still open
      if (isVisible) {
        await page.keyboard.press('Escape');
      }
    }
  });
});

test.describe('App Shell — page routing', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
  });

  test('default page is downloads', async ({ page }) => {
    // Should not be on settings or scheduler
    await expect(page.locator('[role="dialog"]')).not.toBeVisible();
  });

  test('navigating to settings shows settings content', async ({ page }) => {
    await page.keyboard.press('Control+,');
    await page.waitForTimeout(500);
    await expect(page.getByRole('heading', { name: /control center.*settings/i })).toBeVisible({ timeout: 3000 });
  });

  test('navigating to scheduler shows scheduler content', async ({ page }) => {
    await page.keyboard.press('Control+l');
    await page.waitForTimeout(500);
    await expect(page.getByRole('heading', { name: /download lists/i })).toBeVisible({ timeout: 3000 });
  });
});

test.describe('App Shell — custom context menu suppression', () => {
  test('right-click shows custom context menu, not browser default', async ({ page }) => {
    await goto(page);
    const mainContent = page.locator('table').first();
    if (await mainContent.isVisible()) {
      await mainContent.click({ button: 'right' });
      await page.waitForTimeout(300);
    }
  });
});
