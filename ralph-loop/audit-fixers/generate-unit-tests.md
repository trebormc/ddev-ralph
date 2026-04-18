<!-- #ddev-generated -->
# Generate Unit Tests for All Custom Modules

## Objective

Generate missing PHPUnit unit tests for all custom modules and themes, and fix any failing tests, using `drush audit:run phpunit` to detect coverage gaps. Work iteratively — one module at a time — until the audit reports zero errors, zero warnings, and adequate test coverage across all custom code. Unit tests cover **pure PHP logic** that can be tested without the Drupal kernel.

**Reference skill**: `drupal-unit-test` — load it for mock templates, service patterns, and annotation style.
**Decision rule**: `drupal-testing` — see the decision tree to confirm a class belongs in Unit tests (not Kernel).

## Requirements

### Core Loop

1. Detect Drupal version (D10 vs D11) — affects data provider syntax and PHPUnit version
2. Run `drush audit:run phpunit --format=json` to get test coverage gaps and failures
3. Parse the JSON output — identify modules with **no tests** first, then modules with **insufficient tests**
4. For each module: read source code, identify classes suitable for unit testing, write tests
5. Run the tests for that module to verify they pass
6. Run PHPCS on the new test files to ensure coding standards
7. Re-run the audit to verify improvements and detect regressions
8. Repeat until `summary.errors` is **0** and `summary.warnings` is **0**

### What Belongs in Unit Tests

Classes that can be instantiated **without the Drupal container**:
- Utility classes, value objects, data transformations
- Parsers, validators, calculators
- Services where all dependencies can be mocked (max 4-5 mocks)
- Form `buildForm()` structure and `validateForm()` logic (with mocked dependencies)
- Plugin classes (with DI via reflection for mock injection)
- Controllers (with mocked services)

### What Does NOT Belong in Unit Tests

- Services that need entity storage, database, or config from the container → **Kernel test**
- Entity CRUD operations → **Kernel test**
- Form UI rendering and submission → **Functional test**
- JavaScript/AJAX → **FunctionalJavascript test**

**Rule**: If you need to mock more than 4-5 services, the class is better tested with a Kernel test.

### Test Generation Strategy

- **Modules with zero tests** (highest priority):
  - Identify all service classes, controllers, forms, and plugin classes
  - Start with service classes (most reusable, easiest to unit test)
  - Write tests for all public methods with meaningful logic
  - Skip trivial getters/setters unless they contain logic

- **Modules with insufficient coverage**:
  - Read existing test files to understand patterns already in use
  - Identify untested public methods in each class
  - Add test methods for uncovered code paths
  - Use `@dataProvider` for methods with multiple branches

- **Failing tests**:
  - Analyze the failure message — determine if the test or the code is wrong
  - If test is wrong: fix the test (wrong mock setup, outdated assertion)
  - If code is wrong: fix the code, then verify the test passes
  - NEVER delete a failing test — fix it

### Unit Test Standards

**CRITICAL: PHPDoc annotations — NOT PHP 8 attributes.** Drupal 10 uses PHPUnit 9.x which does not support attributes.

| Use THIS (PHPDoc) | NOT this (PHP 8 attribute) |
|---|---|
| `@coversDefaultClass \My\Class` | `#[CoversClass(MyClass::class)]` |
| `@covers ::methodName` | `#[Covers('methodName')]` |
| `@group mymodule` | `#[Group('mymodule')]` |
| `@dataProvider providerName` | `#[DataProvider('providerName')]` |

1. Base class: `Drupal\Tests\UnitTestCase` (never bare `PHPUnit\Framework\TestCase`)
2. `declare(strict_types=1)` as first line after `<?php`
3. `@coversDefaultClass` on every test class
4. `@covers ::methodName` on every test method
5. `@group module_name` on all test classes
6. All dependencies mocked — no DB, filesystem, or HTTP
7. No `\Drupal::service()` in tests — use dependency injection via constructor mocks
8. No `sleep()` in tests
9. Data providers must be `static` methods (D10+D11 compatible)
10. Never use `withConsecutive()` (removed in PHPUnit 10)
11. Prefer `assertSame()` over `assertEquals()`
12. 2-space indentation (Drupal coding standard)
13. Test through public API only — reflection allowed ONLY for injecting mock dependencies

### Test File Structure

```
$DDEV_DOCROOT/modules/custom/<module_name>/
└── tests/
    └── src/
        └── Unit/
            ├── Service/
            │   └── MyServiceTest.php
            ├── Plugin/
            │   └── Block/
            │       └── MyBlockTest.php
            ├── Form/
            │   └── MyFormTest.php
            └── Controller/
                └── MyControllerTest.php
```

Namespace: `Drupal\Tests\<module_name>\Unit\<SubDir>`

### Common Mock Patterns

```php
// Config Factory
$config = $this->createMock(ImmutableConfig::class);
$config->method('get')
  ->willReturnCallback(fn(string $key) => $values[$key] ?? NULL);
$this->configFactory->method('get')->willReturn($config);

// Entity Query (always include accessCheck)
$query = $this->createMock(QueryInterface::class);
$query->method('accessCheck')->willReturnSelf();
$query->method('condition')->willReturnSelf();
$query->method('execute')->willReturn(['id1', 'id2']);
$storage = $this->createMock(EntityStorageInterface::class);
$storage->method('getQuery')->willReturn($query);
$this->entityTypeManager->method('getStorage')->willReturn($storage);

// Logger with assertion
$this->logger = $this->createMock(LoggerInterface::class);
$this->logger->expects($this->once())->method('error')
  ->with($this->stringContains('failed'));

// String translation (from UnitTestCase)
// Already available via $this->getStringTranslationStub()
```

### Plugin Test Setup (Reflection for DI)

```php
protected function setUp(): void {
  parent::setUp();
  $this->block = new MyBlock([], 'my_block', ['id' => 'my_block', 'provider' => 'mymodule']);
  // Inject mock via reflection (ONLY for DI, never for testing logic)
  $this->entityTypeManager = $this->createMock(EntityTypeManagerInterface::class);
  $ref = new \ReflectionClass($this->block);
  $prop = $ref->getProperty('entityTypeManager');
  $prop->setAccessible(TRUE);
  $prop->setValue($this->block, $this->entityTypeManager);
}
```

### Per-Module Workflow

1. **Identify the module** from audit findings (no tests or insufficient coverage)
2. **Read source files**: Scan `src/` for services, controllers, forms, plugins
3. **Read existing tests** (if any): Understand mock patterns already in use
4. **Classify each class**: Can it be unit tested? Or does it need Kernel test?
5. **Prioritize**:
   - Services (`src/Service/`) — most reused, highest value
   - Plugin classes (`src/Plugin/`) — blocks, fields
   - Form classes (`src/Form/`) — config forms, entity forms
   - Controllers (`src/Controller/`) — route handlers
   - Event subscribers (`src/EventSubscriber/`) — event handlers
6. **Write test class** for each eligible source class
7. **Run the test file** to verify it passes
8. **Run PHPCS** on the test file
9. **Move to next class**, then next module

### What NOT to Do

- Do NOT generate kernel or functional tests — this prompt is **unit tests only**
- Do NOT modify contrib modules — only test custom code
- Do NOT create tests that depend on database or Drupal bootstrap
- Do NOT use `\Drupal::setContainer()` in test methods (only in `setUp()` if absolutely needed)
- Do NOT add `@phpstan-ignore` or `phpcs:ignore` to test code
- Do NOT change existing source code behavior to make tests pass (unless it is clearly a bug)
- Do NOT test Drupal core or contrib module functionality
- Do NOT write tests for trivial one-line getters with no logic

## Technical Constraints

- All commands via `ssh web`
- Use `$DDEV_DOCROOT` for paths
- `declare(strict_types=1)` on all PHP files
- Drupal coding standards: 2-space indentation, Drupal + DrupalPractice sniffs
- PHPDoc annotations only — no PHP 8 attributes
- Data providers must be `static` (D10+D11)
- Never use `withConsecutive()`

## Audit Commands

```bash
# Full unit test audit (detect missing tests and failures)
ssh web drush audit:run phpunit --format=json

# Filtered by specific module
ssh web drush audit:run phpunit --filter="module:MODULE_NAME" --format=json

# See which modules have test issues
ssh web drush audit:filters phpunit --format=json

# Run PHPUnit directly for a specific module
ssh web ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/src/Unit/

# Run PHPUnit for a specific test file
ssh web ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/src/Unit/Service/MyServiceTest.php

# PHPCS on test files
ssh web ./vendor/bin/phpcs --standard=Drupal,DrupalPractice $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/src/Unit/
```

## Error Handling During Loop

### If a new test fails
1. Run the specific test file in isolation to get the full error output
2. Check mock setup matches actual method signatures in the source class
3. Check for missing `parent::setUp()` call
4. Check for `$this->getStringTranslationStub()` conflicts with manual TranslationInterface mocks
5. Fix the test and re-run — do NOT leave failing tests behind

### If PHPCS errors appear in test code
1. Run PHPCBF on the specific test file first (auto-fix formatting)
2. Fix remaining issues manually (line length, missing PHPDoc, indentation)
3. Re-verify before moving to next class

### If a class is untestable as a unit test
- If it requires database access → skip, create Beads task for Kernel test
- If it extends a complex base class that cannot be mocked → skip, create Beads task
- If constructor requires Drupal bootstrap → skip, document reason
- ONLY skip truly untestable classes — most Drupal services ARE unit-testable with proper mocking

## Verification Commands

```bash
# Primary: Audit module PHPUnit check
ssh web drush audit:run phpunit --format=json

# Run all unit tests for a module
ssh web ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/src/Unit/

# Verify new test files pass coding standards
ssh web drush audit:run phpcs --filter="module:MODULE_NAME" --format=json

# Verify no PHPStan errors introduced
ssh web drush audit:run phpstan --filter="module:MODULE_NAME" --format=json
```

## Success Criteria

1. `drush audit:run phpunit --format=json` returns `summary.errors: 0`
2. `drush audit:run phpunit --format=json` returns `summary.warnings: 0`
3. All new tests pass with 0 errors and 0 failures
4. All test files pass PHPCS (Drupal + DrupalPractice)
5. `drush audit:run phpstan --format=json` still passes (no regressions)
6. Every custom module has at least one unit test class (for classes with testable logic)
7. Classes that need Kernel/Functional tests are documented as Beads tasks, not forced into unit tests

## If Blocked

- If a module has no unit-testable classes (only hooks or entity-dependent code) → create Beads task for Kernel tests, skip unit tests for that module
- If the Audit module is not installed → fall back to running `phpunit` directly and manually scanning for untested modules
- If a class requires DB/entity storage → skip it for unit tests, create Beads task for Kernel test
- If fixing a failing test requires changing a public API → create Beads task, skip that test
- If test coverage measurement requires Xdebug/PCOV and it is not available → focus on test existence and passing status
- If mock count exceeds 4-5 → the class is better suited for Kernel test, skip and document
