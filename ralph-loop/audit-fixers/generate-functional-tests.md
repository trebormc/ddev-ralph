<!-- #ddev-generated -->
# Generate Functional Tests for All Custom Modules

## Objective

Generate missing Functional tests (`BrowserTestBase`) for all custom modules that have forms, routes with permission checks, admin pages, or any functionality that requires verifying rendered HTML output via HTTP. Functional tests simulate a full browser session without JavaScript.

**Reference skill**: `drupal-functional-test` — load it for templates, patterns, and anti-patterns.

## Requirements

### Core Loop

1. Detect Drupal version (D10 vs D11)
2. List all custom modules and identify code that needs Functional tests:
   - Configuration forms (`src/Form/` extending `ConfigFormBase` or `FormBase`)
   - Admin pages and settings pages
   - Routes with permission requirements (verify 200 with permission, 403 without)
   - Content creation/editing/deletion via UI
   - Block placement and rendering
   - Status/error message display
   - Redirects and route responses
3. Check existing Functional tests — adapt style, do not duplicate
4. For each module: generate Functional test classes
5. Run the tests to verify they pass
6. Run PHPCS on new test files
7. Repeat until all modules with UI components have Functional tests

### What Needs Functional Tests (NOT Kernel)

Use Functional tests ONLY when you need:
- To submit a form via the UI and verify the result
- To verify HTTP status codes (200, 403, 404) for routes
- To check rendered HTML output (page text, elements, links)
- To verify blocks appear in the correct regions
- To test permission-based access via HTTP requests

Do NOT use Functional tests for:
- Service logic, entity CRUD, queries → Kernel test (10x faster)
- Form validation/submit handler logic → Kernel test
- JavaScript/AJAX → FunctionalJavascript test
- Pure PHP logic → Unit test

**Rule: If you can test the same thing with a Kernel test, use Kernel test.**

### Functional Test Standards

```php
<?php
declare(strict_types=1);

namespace Drupal\Tests\MODULE\Functional;

use Drupal\Tests\BrowserTestBase;

/**
 * Tests DESCRIPTION.
 *
 * @group MODULE
 */
class NameTest extends BrowserTestBase {

  protected $defaultTheme = 'stark';       // REQUIRED — always 'stark' for speed
  protected static $modules = ['MODULE'];

  protected function setUp(): void {
    parent::setUp();
    // Create users, content types, etc.
  }

}
```

**CRITICAL**: `$defaultTheme = 'stark'` is REQUIRED. Without it the test fails.

### Per-Module Workflow

1. **Identify routes** — read `MODULE.routing.yml` for all paths and permissions
2. **Identify forms** — read `src/Form/` for admin forms and entity forms
3. **Plan test classes**:
   - One test class per form (e.g., `SettingsFormTest`)
   - One test class for permission/access testing (e.g., `AccessTest`)
   - One test class for page output (e.g., `PageOutputTest`)
4. **Write tests** covering:
   - Form displays correctly (fields exist, default values shown)
   - Form submits successfully (config saved, status message shown)
   - Form validation catches invalid input (error messages)
   - Routes return correct HTTP codes per permission
   - Blocks appear when placed
5. **Run each test file** to verify it passes
6. **Run PHPCS** on new files

### Common Test Patterns

**Config form test**: Load form → verify fields → submit → verify saved → reload → verify values persist

**Permission test**: Create user with permission → verify 200. Create user without → verify 403.

**Content creation**: Login → go to node/add → submit form → verify created message → verify node exists

**Block test**: Place block via `drupalPlaceBlock()` → load page → verify block content visible

### Key Assertions

```php
$assert = $this->assertSession();
$assert->statusCodeEquals(200);
$assert->pageTextContains('Expected text');
$assert->fieldExists('field_name');
$assert->fieldValueEquals('field_name', 'expected');
$assert->statusMessageContains('saved', 'status');
$assert->statusMessageExists('error');
$assert->elementExists('css', '.my-class');
$assert->linkExists('Link text');
```

### Key Navigation Methods

```php
$this->drupalGet('admin/config/my-module/settings');
$this->drupalLogin($user);
$this->submitForm(['field' => 'value'], 'Save configuration');
$this->clickLink('Edit');
$user = $this->drupalCreateUser(['permission_name']);
$node = $this->drupalCreateNode(['type' => 'article']);
```

### What NOT to Do

- Do NOT test business logic with Functional tests if Kernel works → Kernel is 10x faster
- Do NOT forget `$defaultTheme` → test will fail
- Do NOT use `drupalPostForm()` → deprecated, use `submitForm()`
- Do NOT depend on theme-specific markup → search by text or your own CSS classes
- Do NOT use `statusCodeEquals()` if you plan to migrate to FunctionalJS later (unsupported)
- Do NOT modify contrib modules
- Do NOT add `phpcs:ignore` to test code

## Technical Constraints

- All commands via `ssh web`
- Use `$DDEV_DOCROOT` for paths
- `declare(strict_types=1)` on all files
- `$defaultTheme = 'stark'` on every test class
- Drupal coding standards: 2-space indentation
- Data providers must be `static` (D10+D11 compatible)
- PHPDoc annotations only — no PHP 8 attributes

## Audit Commands

```bash
# Test audit
ssh web ./vendor/bin/drush audit:run phpunit --format=json

# Run Functional tests for a module
ssh web ./vendor/bin/phpunit -c core --testsuite functional $DDEV_DOCROOT/modules/custom/MODULE/

# Run specific test
ssh web ./vendor/bin/phpunit -c core --filter testFormSavesValues

# PHPCS on test files
ssh web ./vendor/bin/phpcs --standard=Drupal,DrupalPractice $DDEV_DOCROOT/modules/custom/MODULE/tests/src/Functional/
```

## Success Criteria

1. Every module with forms/routes has Functional tests
2. All config forms tested: display, submit, validation, permissions
3. All routes tested for correct HTTP status codes and permissions
4. All generated tests pass: `phpunit --testsuite functional --group MODULE` exits 0
5. All test files pass PHPCS
6. No regressions in existing tests

## If Blocked

- If Drupal install takes too long in tests → reduce `$modules` to the minimum, use `'testing'` profile (default)
- If `submitForm()` fails → verify field names match HTML form field names (use browser inspection or `$this->drupalGet()` + check source)
- If permission tests return wrong codes → verify the permission string matches exactly what is in `MODULE.permissions.yml`
- If blocks do not appear → verify block plugin ID and region name match the theme
- If a form requires complex entity setup → consider using Kernel test for the handler logic instead
