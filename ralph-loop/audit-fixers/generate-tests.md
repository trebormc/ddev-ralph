<!-- #ddev-generated -->
# Generate All Missing Tests for Drupal Project

## Objective

Analyze test coverage across all custom modules and themes, determine which types of tests are missing (Unit, Kernel, Functional, FunctionalJavascript, Behat, Playwright), and generate them iteratively. This is the **orchestrator prompt** — it analyzes the full project and creates tasks for each (module, test_type) pair that needs work.

**Reference skills**: `drupal-testing` (decision tree), `drupal-unit-test`, `drupal-kernel-test`, `drupal-functional-test`, `drupal-functionaljs-test`, `drupal-behat-test`, `drupal-playwright-test`.

## Requirements

### Phase 1 — Project Analysis (Planning Phase)

Before creating any tasks, gather this information:

1. **Detect Drupal version**:
   ```bash
   ssh web php -r "include '$DDEV_DOCROOT/core/lib/Drupal.php'; echo \Drupal::VERSION;"
   ```
   This determines PHPUnit version, data provider syntax, and ChromeDriver config.

2. **Check existing test infrastructure**:
   ```bash
   # PHPUnit config
   ssh web test -f phpunit.xml && echo "phpunit.xml exists" || echo "no phpunit.xml"
   ssh web test -f phpunit.xml.dist && echo "phpunit.xml.dist exists" || echo "no phpunit.xml.dist"

   # Behat
   ssh web test -f behat.yml && echo "behat exists" || echo "no behat"
   ssh web test -f behat.yml.dist && echo "behat.dist exists" || echo "no behat.dist"

   # Playwright
   ssh web test -f test/playwright/playwright.config.ts && echo "playwright exists" || echo "no playwright"
   ```

3. **Get test coverage audit** (if Audit module is available):
   ```bash
   ssh web ./vendor/bin/drush audit:run phpunit --format=json
   ssh web ./vendor/bin/drush audit:filters phpunit --format=json
   ```
   If Audit module is not installed, fall back to manual scanning:
   ```bash
   # List custom modules
   find $DDEV_DOCROOT/modules/custom -name "*.info.yml" -maxdepth 2

   # Check which have tests
   for module_dir in $DDEV_DOCROOT/modules/custom/*/; do
     module=$(basename "$module_dir")
     unit=$(find "$module_dir" -path "*/tests/src/Unit/*.php" 2>/dev/null | wc -l)
     kernel=$(find "$module_dir" -path "*/tests/src/Kernel/*.php" 2>/dev/null | wc -l)
     functional=$(find "$module_dir" -path "*/tests/src/Functional/*.php" 2>/dev/null | wc -l)
     functionaljs=$(find "$module_dir" -path "*/tests/src/FunctionalJavascript/*.php" 2>/dev/null | wc -l)
     echo "$module: unit=$unit kernel=$kernel functional=$functional functionaljs=$functionaljs"
   done
   ```

4. **Analyze each module's source code** to classify what tests are needed:
   - Services (`src/Service/`) → Kernel tests (or Unit if pure PHP)
   - Entities (`src/Entity/`) → Kernel tests
   - Plugins (`src/Plugin/`) → Kernel tests (discovery) or Unit (isolated logic)
   - Forms (`src/Form/`) → Functional tests (UI rendering) + Kernel (validation logic)
   - Controllers (`src/Controller/`) → Functional tests (HTTP + permissions)
   - Event subscribers (`src/EventSubscriber/`) → Kernel tests
   - Access checkers (`src/Access/`) → Kernel tests
   - Classes with AJAX (`#ajax`, `AjaxResponse`) → FunctionalJavascript tests
   - Utility classes with no Drupal deps → Unit tests

5. **Create Beads tasks** in this priority order:

   **P0 — Kernel tests** (highest value, most code coverage per test):
   - One task per module that needs Kernel tests
   - Title format: `Generate Kernel tests for <module_name>`

   **P1 — Unit tests** (fast, easy to write):
   - One task per module with pure PHP utility classes
   - Title format: `Generate Unit tests for <module_name>`

   **P1 — Functional tests** (forms and permissions):
   - One task per module with forms or route-based controllers
   - Title format: `Generate Functional tests for <module_name>`

   **P2 — FunctionalJavascript tests** (only where AJAX exists):
   - One task per module with AJAX forms or JS-dependent UI
   - Title format: `Generate FunctionalJavascript tests for <module_name>`

   **P2 — Behat tests** (only if project uses Behat):
   - One task for critical user flows
   - Title format: `Generate Behat scenarios for <flow_description>`

   **P3 — Playwright tests** (only if project uses Playwright or needs visual regression):
   - One task for visual regression setup
   - Title format: `Generate Playwright tests for <scope>`

### Phase 2 — Execution (Per Task)

For each task created in Phase 1:

1. **Read the task title** to determine the module and test type
2. **Read the module's source code** — understand every class that needs testing
3. **Check existing tests** — adapt style to match, do not duplicate
4. **Apply the decision tree** from the `drupal-testing` rule:
   - Use the corresponding skill for the test type
   - Follow all templates and anti-patterns from the skill
5. **Generate test files** in the correct directory structure
6. **Run the tests** to verify they pass:
   ```bash
   ssh web ./vendor/bin/phpunit -c core --group MODULE_NAME
   ```
7. **Run PHPCS** on new test files:
   ```bash
   ssh web ./vendor/bin/phpcs --standard=Drupal,DrupalPractice MODULE_PATH/tests/
   ```
8. **Close the task** with a summary of what was generated

### Test Generation Rules

- **Drupal 10+11 compatibility**: PHPDoc annotations (NOT PHP 8 attributes), static data providers
- **`declare(strict_types=1)`** on every file
- **`@group module_name`** on every test class
- **Prefer `assertSame()` over `assertEquals()`**
- **Never use `sleep()`** — use waits in JS tests
- **Never use `withConsecutive()`** — removed in PHPUnit 10
- **One test per behavior**, not per method
- **Only test custom code** — never contrib or core

### What NOT to Do

- Do NOT generate ALL test types for every module — only what makes sense for each class
- Do NOT modify contrib modules
- Do NOT add `@phpstan-ignore` or `phpcs:ignore` to test code
- Do NOT change source code behavior to make tests pass (unless it is clearly a bug)
- Do NOT generate tests for trivial getters with no logic
- Do NOT create FunctionalJavascript tests when Functional tests suffice
- Do NOT create Behat/Playwright if the project has no setup for them

## Technical Constraints

- All commands via `ssh web`
- Use `$DDEV_DOCROOT` for paths (never hardcode `web/`)
- Drupal coding standards: 2-space indentation
- All test types must pass both PHPCS and the tests themselves
- If a class requires too many mocks (>4-5) for a Unit test, use Kernel test instead

## Success Criteria

The task is complete when:

1. Every custom module has at least one test class (Unit, Kernel, or Functional)
2. All generated tests pass: `phpunit -c core --group MODULE` exits 0
3. All test files pass PHPCS (Drupal + DrupalPractice)
4. No regressions introduced in existing tests
5. Test types match the code they test (Kernel for services, Functional for forms, etc.)
6. If Audit module is available: `drush audit:run phpunit --format=json` shows improvement

## Verification Commands

```bash
# Run all tests for a module
ssh web ./vendor/bin/phpunit -c core --group MODULE_NAME

# Run by suite
ssh web ./vendor/bin/phpunit -c core --testsuite unit $DDEV_DOCROOT/modules/custom/MODULE/
ssh web ./vendor/bin/phpunit -c core --testsuite kernel $DDEV_DOCROOT/modules/custom/MODULE/
ssh web ./vendor/bin/phpunit -c core --testsuite functional $DDEV_DOCROOT/modules/custom/MODULE/

# PHPCS on test files
ssh web ./vendor/bin/phpcs --standard=Drupal,DrupalPractice $DDEV_DOCROOT/modules/custom/MODULE/tests/

# Full audit (if available)
ssh web ./vendor/bin/drush audit:run phpunit --format=json

# Behat (if applicable)
ssh web ./vendor/bin/behat --config=behat.yml

# Playwright (if applicable)
npx playwright test
```

## If Blocked

- If the Audit module is not installed → scan modules manually with `find` and generate tests based on source code analysis
- If a class is untestable as Unit (needs DB/container) → use Kernel test instead
- If Kernel tests fail due to missing schema → check `installEntitySchema()` and `installConfig()` calls
- If Functional tests fail with no theme → ensure `$defaultTheme = 'stark'` is set
- If FunctionalJavascript tests fail → verify ChromeDriver is running and use `goog:chromeOptions` for D11
- If Behat is not installed → skip Behat tasks, suggest `composer require --dev drupal/drupal-extension`
- If Playwright is not installed → skip Playwright tasks
- If a module has only `.module` hook code with no classes → skip or suggest extracting to a service first
- If fixing a test requires changing a public API → create a new Beads task for the refactor, skip that test
