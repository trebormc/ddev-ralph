<!-- #ddev-generated -->
# Generate FunctionalJavascript Tests for Custom Modules

## Objective

Generate missing FunctionalJavascript tests (`WebDriverTestBase`) for custom modules that have AJAX forms, entity reference autocompletes, modals, drag-and-drop, visibility toggles, CKEditor interactions, or any UI that depends on JavaScript execution. These are the **slowest PHPUnit tests** — only generate them when JavaScript is genuinely required.

**Reference skill**: `drupal-functionaljs-test` — load it for templates, patterns, and anti-patterns.

## Requirements

### Core Loop

1. Detect Drupal version (D10 vs D11) — D11 requires `goog:chromeOptions`
2. Scan all custom modules for JavaScript-dependent code:
   - Forms with `#ajax` callbacks
   - Entity reference fields with autocomplete
   - Form elements using `#states` with complex visibility logic
   - Modal dialogs (`dialog` library)
   - Drag-and-drop interfaces
   - CKEditor integration
   - Custom JavaScript behaviors (`Drupal.behaviors`)
3. Check existing FunctionalJavascript tests — adapt style, do not duplicate
4. For each module with JS-dependent UI: generate FunctionalJavascript tests
5. Run the tests to verify they pass
6. Run PHPCS on new test files
7. Repeat until all AJAX/JS functionality has tests

### How to Identify JS-Dependent Code

```bash
# Find forms with AJAX callbacks
ssh web grep -rl "#ajax" $DDEV_DOCROOT/modules/custom/ --include="*.php"

# Find #states usage
ssh web grep -rl "#states" $DDEV_DOCROOT/modules/custom/ --include="*.php"

# Find entity reference autocomplete fields
ssh web grep -rl "entity_autocomplete\|autocomplete_route" $DDEV_DOCROOT/modules/custom/ --include="*.php" --include="*.yml"

# Find modal/dialog usage
ssh web grep -rl "dialog\|modal\|AjaxResponse" $DDEV_DOCROOT/modules/custom/ --include="*.php"

# Find custom JS behaviors
ssh web grep -rl "Drupal.behaviors" $DDEV_DOCROOT/modules/custom/ --include="*.js"
```

### What Needs FunctionalJavascript Tests

- AJAX form elements (select that reloads dependent fields)
- Entity reference autocomplete widgets
- Modal/dialog interactions (open, interact, close)
- `#states` with complex conditional visibility
- CKEditor text formatting
- Drag-and-drop reordering
- Any form behavior that only works with JavaScript enabled

### What Does NOT Need FunctionalJavascript Tests

- Simple forms without AJAX → Functional test
- Service logic → Kernel test
- Permission checks → Functional test
- Pure PHP → Unit test
- E2E user flows → Behat or Playwright

### GOLDEN RULE: Never sleep(), Always Waits

```php
$assert = $this->assertSession();

// After AJAX (most common)
$assert->assertWaitOnAjaxRequest();

// Wait for element visible
$element = $assert->waitForElementVisible('css', '.selector');
$this->assertNotEmpty($element);

// Wait for element removed
$assert->waitForElementRemoved('css', '.spinner');

// Wait for autocomplete
$assert->waitOnAutocomplete();

// Wait for text
$assert->waitForText('Expected text');

// Custom JS condition (last resort)
$this->getSession()->wait(5000, 'jQuery.active === 0');
```

### FunctionalJavascript Test Template

```php
<?php
declare(strict_types=1);

namespace Drupal\Tests\MODULE\FunctionalJavascript;

use Drupal\FunctionalJavascriptTests\WebDriverTestBase;

/**
 * Tests DESCRIPTION.
 *
 * @group MODULE
 */
class NameTest extends WebDriverTestBase {

  protected $defaultTheme = 'stark';
  protected static $modules = ['MODULE'];

  protected function setUp(): void {
    parent::setUp();
  }

  public function testAjaxBehavior(): void {
    $this->drupalLogin($this->adminUser);
    $this->drupalGet('route/path');

    $page = $this->getSession()->getPage();
    $assert = $this->assertSession();

    // Trigger AJAX
    $page->selectFieldOption('field_name', 'value');
    $assert->assertWaitOnAjaxRequest();

    // Verify result
    $element = $assert->waitForElementVisible('css', '.result');
    $this->assertNotEmpty($element);
  }

}
```

### Critical Difference from BrowserTestBase

`statusCodeEquals()` does **NOT work** in WebDriverTestBase. The Selenium2 driver has no access to HTTP codes. Verify access with `pageTextContains()` or `elementExists()` instead.

### ChromeDriver Configuration

Drupal 10.3+ and 11 require `goog:chromeOptions`:
```xml
<env name="MINK_DRIVER_ARGS_WEBDRIVER"
     value='["chrome", {"browserName":"chrome","goog:chromeOptions":{"args":["--disable-gpu","--headless","--no-sandbox","--disable-dev-shm-usage"]}}, "http://127.0.0.1:9515"]'/>
```

### What NOT to Do

- **NEVER** use `sleep()` — this is the #1 cause of flaky tests
- Do NOT use `statusCodeEquals()` — does not work with WebDriver
- Do NOT write 15+ interaction steps — that is an E2E flow, use Behat/Playwright
- Do NOT test things that do not need JS — use Functional test instead
- Do NOT forget to wait after AJAX — will pass locally, fail in CI
- Do NOT modify contrib modules
- Do NOT add `phpcs:ignore` to test code

## Technical Constraints

- All commands via `ssh web`
- Use `$DDEV_DOCROOT` for paths
- `declare(strict_types=1)` on all files
- `$defaultTheme = 'stark'` required
- ChromeDriver must be running for test execution
- PHPDoc annotations only — no PHP 8 attributes
- Data providers must be `static` (D10+D11)

## Audit Commands

```bash
# Verify ChromeDriver is available
ssh web chromedriver --version 2>/dev/null || echo "ChromeDriver not found"

# Run FunctionalJavascript tests
ssh web ./vendor/bin/phpunit -c core --testsuite functional-javascript $DDEV_DOCROOT/modules/custom/MODULE/

# Run specific test
ssh web ./vendor/bin/phpunit -c core --filter testAjaxBehavior

# PHPCS on test files
ssh web ./vendor/bin/phpcs --standard=Drupal,DrupalPractice $DDEV_DOCROOT/modules/custom/MODULE/tests/src/FunctionalJavascript/
```

## Success Criteria

1. Every module with AJAX/JS-dependent forms has FunctionalJavascript tests
2. All tests use proper waits (no `sleep()`)
3. All generated tests pass with ChromeDriver
4. All test files pass PHPCS
5. No regressions in existing tests
6. Tests are focused on JS behavior only — non-JS aspects tested elsewhere

## If Blocked

- If ChromeDriver is not installed → document as a prerequisite, skip FunctionalJS tests
- If tests are flaky → replace `sleep()` with proper `waitFor*` methods, add `assertWaitOnAjaxRequest()`
- If `statusCodeEquals()` fails → replace with `pageTextContains()` or `elementExists()`
- If AJAX forms do not trigger → verify the `#ajax` callback is correct and the trigger element is targeted properly
- If an interaction sequence is too long (>10 steps) → split into Behat or Playwright E2E test
- If autocomplete does not return results → ensure the referenced entities exist and the user has access
