<!-- #ddev-generated -->
# Generate Playwright E2E Tests for Drupal Project

## Objective

Generate Playwright end-to-end tests for a Drupal project: visual regression testing, cross-browser verification, accessibility audits, and critical user flow smoke tests. Playwright is the **official replacement for Nightwatch in Drupal core** (November 2025).

**Reference skill**: `drupal-playwright-test` — load it for templates, patterns, and configuration.

**PREREQUISITE**: Use this prompt when the project needs E2E tests but does NOT use Behat, OR when visual regression / cross-browser testing is specifically needed regardless of Behat.

## Requirements

### Pre-Check (Planning Phase)

Check if Playwright is already set up:

```bash
# Check for Playwright config
test -f test/playwright/playwright.config.ts && echo "playwright configured" || echo "no playwright config"
test -f playwright.config.ts && echo "playwright configured (root)" || echo "not in root"

# Check for existing tests
find . -name "*.spec.ts" -path "*/playwright/*" 2>/dev/null | head -20
find . -name "*.spec.ts" -path "*/test/*" 2>/dev/null | head -20

# Check DDEV Playwright add-on
docker ps --filter "name=playwright" --format "{{.Names}}" 2>/dev/null
```

If Playwright is NOT set up, create setup tasks first:
1. `mkdir -p test/playwright`
2. Initialize Playwright config
3. Install dependencies
Then proceed with test generation.

### Core Loop

1. Identify what needs E2E testing:
   - Homepage and key landing pages (smoke tests)
   - Content type pages (article, page, etc.)
   - Admin pages and configuration forms
   - Responsive layouts (mobile, tablet, desktop)
   - Accessibility compliance (WCAG 2.0 AA)
   - Critical user flows (login, content creation, search)
2. Check existing `.spec.ts` files — adapt style, do not duplicate
3. Generate test files following Playwright best practices
4. Generate authentication fixtures if needed
5. Run tests to verify they pass
6. Commit baseline screenshots (for visual regression)
7. Repeat until coverage is adequate

### Test Categories

#### 1. Smoke Tests (P0 — always generate)

Quick tests that verify the site is working:

```typescript
import { test, expect } from '@playwright/test';

test.describe('Smoke tests', () => {
  test('homepage loads', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('body')).toBeVisible();
    await expect(page).toHaveTitle(/.+/);
  });

  test('user login page loads', async ({ page }) => {
    await page.goto('/user/login');
    await expect(page.getByLabel('Username')).toBeVisible();
    await expect(page.getByLabel('Password')).toBeVisible();
  });

  test('404 page works', async ({ page }) => {
    const response = await page.goto('/nonexistent-page-12345');
    expect(response?.status()).toBe(404);
  });
});
```

#### 2. Visual Regression (P1 — high value)

```typescript
test.describe('Visual regression', () => {
  test('homepage', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('homepage.png', {
      maxDiffPixelRatio: 0.01,
      fullPage: true,
    });
  });

  test('mobile homepage', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('homepage-mobile.png', {
      maxDiffPixelRatio: 0.01,
      fullPage: true,
    });
  });
});
```

#### 3. Accessibility (P1)

```typescript
import AxeBuilder from '@axe-core/playwright';

test.describe('Accessibility', () => {
  test('homepage meets WCAG 2.0 AA', async ({ page }) => {
    await page.goto('/');
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze();
    expect(results.violations).toEqual([]);
  });
});
```

Requires: `npm install --save-dev @axe-core/playwright`

#### 4. Authentication Flows (P1)

```typescript
// fixtures/auth.ts
import { test as base, expect } from '@playwright/test';

export const test = base.extend({
  authenticatedPage: async ({ page }, use) => {
    await page.goto('/user/login');
    await page.getByLabel('Username').fill('editor');
    await page.getByLabel('Password').fill('editor_pass');
    await page.getByRole('button', { name: 'Log in' }).click();
    await expect(page.getByText('Log out')).toBeVisible();
    await use(page);
  },
  adminPage: async ({ page }, use) => {
    await page.goto('/user/login');
    await page.getByLabel('Username').fill('admin');
    await page.getByLabel('Password').fill('admin_pass');
    await page.getByRole('button', { name: 'Log in' }).click();
    await expect(page.getByText('Log out')).toBeVisible();
    await use(page);
  },
});
export { expect };
```

#### 5. Critical User Flows (P2)

```typescript
import { test, expect } from '../fixtures/auth';

test.describe('Content creation', () => {
  test('editor creates article', async ({ authenticatedPage: page }) => {
    await page.goto('/node/add/article');
    await page.getByLabel('Title').fill('E2E Test Article');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.locator('.messages--status')).toContainText('has been created');
  });
});
```

### Playwright Configuration

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: [['html', { open: 'never' }], ['list']],
  use: {
    baseURL: process.env.DDEV_PRIMARY_URL || 'https://myproject.ddev.site',
    ignoreHTTPSErrors: true,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    // Add firefox and webkit for CI only:
    // { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    // { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
});
```

### Directory Structure

```
test/playwright/
├── playwright.config.ts
├── package.json
├── fixtures/
│   └── auth.ts
├── tests/
│   ├── smoke.spec.ts
│   ├── visual-regression.spec.ts
│   ├── accessibility.spec.ts
│   ├── content-creation.spec.ts
│   └── admin-config.spec.ts
└── tests/smoke.spec.ts-snapshots/     # Auto-generated baseline screenshots
```

### Selector Best Practices

```typescript
// GOOD - semantic selectors
page.getByRole('button', { name: 'Save' });
page.getByLabel('Title');
page.getByText('has been created');
page.getByRole('heading', { name: 'Create Article' });

// AVOID - fragile CSS selectors
page.locator('#edit-submit');
page.locator('.form-actions > input[type="submit"]');
```

Use `getByRole()`, `getByLabel()`, `getByText()` whenever possible. Fall back to `locator()` with CSS only for Drupal-specific selectors (`.messages--status`, `.node--type-article`).

### What NOT to Do

- Do NOT use `page.waitForTimeout()` except in extreme cases — Playwright has auto-waiting
- Do NOT run multi-browser locally — reserve Firefox/WebKit for CI
- Do NOT test business logic — Playwright is for user-visible behavior
- Do NOT forget to commit baseline screenshots to the repo
- Do NOT hardcode user credentials — use environment variables or fixtures
- Do NOT generate tests for admin-only pages without authentication fixtures

## Technical Constraints

- TypeScript for all test files
- Playwright auto-waiting (no manual waits needed in most cases)
- Screenshots stored relative to test file (auto-managed by Playwright)
- HTTPS with `ignoreHTTPSErrors: true` for DDEV self-signed certs
- Single browser (chromium) locally, multi-browser in CI

## Execution Commands

```bash
# Run all tests
npx playwright test

# Specific test file
npx playwright test tests/smoke.spec.ts

# Single browser
npx playwright test --project=chromium

# Update visual baselines
npx playwright test --update-snapshots

# Interactive UI mode
npx playwright test --ui

# Debug mode
npx playwright test --debug

# Record new tests
npx playwright codegen https://mysite.ddev.site

# View HTML report
npx playwright show-report

# Via DDEV (if ddev-playwright is installed)
ddev playwright test
```

## Success Criteria

1. Playwright is configured with `playwright.config.ts`
2. Smoke tests pass for homepage and key pages
3. Visual regression baselines committed for critical pages
4. Accessibility audit passes WCAG 2.0 AA on homepage
5. Authentication fixtures work for editor and admin roles
6. All tests pass: `npx playwright test` exits 0
7. Tests use semantic selectors (`getByRole`, `getByLabel`)
8. No `waitForTimeout()` calls (use Playwright auto-waiting)

## If Blocked

- If Playwright is not installed → create setup tasks: `mkdir -p test/playwright && npx create-playwright@latest`
- If DDEV Playwright add-on is missing → `ddev add-on get Lullabot/ddev-playwright && ddev restart`
- If `@axe-core/playwright` is not available → skip accessibility tests, create task to install
- If authentication fails → use `drush uli` to generate one-time login links in test fixtures
- If visual regression tests fail on first run → run with `--update-snapshots` to create baselines
- If the project has no content → create test content in a `globalSetup` script or in test `beforeAll`
- If tests are slow → run only chromium locally, reserve multi-browser for CI
