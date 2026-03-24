# Generate and Fix Unit Tests via Audit Module

## Objective

Automatically generate missing PHPUnit **unit tests** for all custom modules and themes, and fix any failing tests, using `drush audit:run phpunit` to detect coverage gaps. Work iteratively — one module at a time — until the audit reports zero errors, zero warnings, and adequate test coverage across all custom code. **Only unit tests** — no kernel tests, no functional tests.

**Reference**: Use the **drupal-unit-test** skill for generation patterns, mock templates, and annotation style.

## Requirements

### Core Loop

1. Run `drush audit:run phpunit --format=json` to get test coverage gaps and failures
2. Parse the JSON output — identify modules with **no tests** first, then modules with **insufficient tests**
3. For each module: read source code, understand public API, write unit tests
4. Run the tests for that module to verify they pass
5. Run PHPCS on the new test files to ensure coding standards
6. Re-run the audit to verify improvements and detect regressions
7. Repeat until `summary.errors` is **0** and `summary.warnings` is **0**

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

### Unit Test Standards (Drupal 10+11 Community Best Practices)

**CRITICAL: Use PHPDoc annotations — NOT PHP 8 attributes.** Drupal 10 uses PHPUnit 9.x which does not support attributes. PHPDoc annotations work in both Drupal 10 and 11.

| Use THIS (PHPDoc) | NOT this (PHP 8 attribute) |
|---|---|
| `@coversDefaultClass \My\Class` | `#[CoversClass(MyClass::class)]` |
| `@covers ::methodName` | `#[Covers('methodName')]` |
| `@group mymodule` | `#[Group('mymodule')]` |
| `@dataProvider providerName` | `#[DataProvider('providerName')]` |

1. **Base class**: Always `Drupal\Tests\UnitTestCase` (never bare `PHPUnit\Framework\TestCase`)
2. **`declare(strict_types=1)`** as first line after `<?php`
3. **`@coversDefaultClass`**: Every test class MUST have this annotation at class level
4. **`@covers ::methodName`**: Every test method MUST specify what it covers
5. **`@group module_name`**: All test classes must have the module's group
6. **`@dataProvider`**: Use for testing multiple scenarios of the same method
7. **All dependencies mocked**: No database, no filesystem, no HTTP, no external services
8. **No `\Drupal::service()`** in tests — use dependency injection via constructor mocks
9. **No `sleep()`** in tests
10. **2-space indentation** (Drupal coding standard)
11. **Lines ≤ 120 chars** for code, ≤ 80 chars for comments
12. **Test through public API only**: No reflection to test private/protected logic
13. **Reflection allowed ONLY for**: Injecting mock dependencies into plugin classes via `setProtectedProperty()`

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

### What NOT to Do

- Do NOT generate kernel tests or functional tests — **unit tests only**
- Do NOT modify contrib modules — only test custom code
- Do NOT create tests that depend on database or Drupal bootstrap
- Do NOT use `\Drupal::setContainer()` in test methods (only in `setUp()` if absolutely needed)
- Do NOT add `@phpstan-ignore` or `phpcs:ignore` to test code
- Do NOT change existing source code behavior to make tests pass (unless it's clearly a bug)
- Do NOT test Drupal core or contrib module functionality — only test YOUR code
- Do NOT write tests for trivial one-line getters with no logic

## Technical Constraints

- All commands via `docker exec $WEB_CONTAINER`
- Use `$DDEV_DOCROOT` for paths
- `declare(strict_types=1)` on all PHP files
- Drupal coding standards: 2-space indentation, Drupal + DrupalPractice sniffs
- PHPUnit 10.x compatible (PHPDoc annotations, NOT PHP 8 attributes)
- Maintain dependency injection patterns
- All extracted test methods must have proper type hints and PHPDoc

## Audit Commands

```bash
# Full unit test audit (detect missing tests and failures)
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpunit --format=json

# Filtered by specific module
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpunit --filter="module:MODULE_NAME" --format=json

# See which modules have test issues
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:filters phpunit --format=json

# Run PHPUnit directly for a specific module
docker exec $WEB_CONTAINER ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/

# Run PHPUnit for a specific test file
docker exec $WEB_CONTAINER ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/src/Unit/Service/MyServiceTest.php

# Run PHPUnit with coverage text output
docker exec $WEB_CONTAINER bash -c 'php -d zend_extension=xdebug.so -d xdebug.mode=coverage ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/ --coverage-text --no-progress'
```

## Development Approach

### Per-Module Workflow

1. **Identify the module** from audit findings (no tests or insufficient coverage)
2. **Read source files**: Scan `src/` directory for services, controllers, forms, plugins
3. **Read existing tests** (if any): Understand mock patterns already in use
4. **Prioritize classes to test**:
   - Services (`src/Service/`) — most reused, highest value
   - Plugin classes (`src/Plugin/`) — blocks, fields, etc.
   - Form classes (`src/Form/`) — config forms, entity forms
   - Controllers (`src/Controller/`) — route handlers
   - Event subscribers (`src/EventSubscriber/`) — event handlers
5. **Write test class** for each source class:
   - Create test file in correct directory (`tests/src/Unit/...`)
   - Set up mocks in `setUp()` method
   - Write test methods for each public method
   - Use `@dataProvider` for methods with multiple code paths
6. **Run the specific test file** to verify it passes
7. **Run PHPCS** on the test file to verify coding standards
8. **Move to next class**, then next module

### Priority Order

1. Modules with **zero tests** — highest value, fills biggest gap
2. Modules with **failing tests** — broken tests block CI/CD
3. Modules with **low coverage** — below audit thresholds
4. Modules with **warnings** — incomplete or risky tests

### Writing Test Classes: Patterns

**Service class test:**
```php
<?php

declare(strict_types=1);

namespace Drupal\Tests\my_module\Unit\Service;

use Drupal\my_module\Service\MyService;
use Drupal\Tests\UnitTestCase;
use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Config\ImmutableConfig;

/**
 * Tests the MyService service.
 *
 * @coversDefaultClass \Drupal\my_module\Service\MyService
 * @group my_module
 */
class MyServiceTest extends UnitTestCase {

  /**
   * The service under test.
   */
  protected MyService $service;

  /**
   * Mock config factory.
   */
  protected ConfigFactoryInterface $configFactory;

  /**
   * {@inheritdoc}
   */
  protected function setUp(): void {
    parent::setUp();
    $this->configFactory = $this->createMock(ConfigFactoryInterface::class);
    $this->service = new MyService($this->configFactory);
  }

  /**
   * Tests processing with valid data.
   *
   * @covers ::process
   */
  public function testProcessWithValidData(): void {
    $config = $this->createMock(ImmutableConfig::class);
    $config->method('get')->willReturn('value');
    $this->configFactory->method('get')->willReturn($config);

    $result = $this->service->process(['key' => 'value']);

    $this->assertIsArray($result);
    $this->assertNotEmpty($result);
  }

  /**
   * Tests processing with various inputs.
   *
   * @covers ::process
   * @dataProvider processDataProvider
   */
  public function testProcessScenarios(array $input, bool $expectedEmpty): void {
    $config = $this->createMock(ImmutableConfig::class);
    $config->method('get')->willReturn('default');
    $this->configFactory->method('get')->willReturn($config);

    $result = $this->service->process($input);

    $this->assertEquals($expectedEmpty, empty($result));
  }

  /**
   * Data provider for testProcessScenarios.
   *
   * @return array
   *   Test scenarios.
   */
  public static function processDataProvider(): array {
    return [
      'valid input' => [['key' => 'value'], FALSE],
      'empty input' => [[], TRUE],
    ];
  }

}
```

**Plugin class test (with reflection for DI):**
```php
/**
 * {@inheritdoc}
 */
protected function setUp(): void {
  parent::setUp();
  // Create plugin instance.
  $configuration = [];
  $plugin_id = 'my_block';
  $plugin_definition = ['id' => 'my_block', 'provider' => 'my_module'];
  $this->block = new MyBlock($configuration, $plugin_id, $plugin_definition);

  // Inject mock dependencies via reflection (ONLY for DI, not for testing logic).
  $this->entityTypeManager = $this->createMock(EntityTypeManagerInterface::class);
  $reflection = new \ReflectionClass($this->block);
  $property = $reflection->getProperty('entityTypeManager');
  $property->setAccessible(TRUE);
  $property->setValue($this->block, $this->entityTypeManager);
}
```

**Form class test:**
```php
/**
 * Tests that buildForm returns correct structure.
 *
 * @covers ::buildForm
 */
public function testBuildFormStructure(): void {
  $form = [];
  $form_state = new FormState();

  $result = $this->form->buildForm($form, $form_state);

  $this->assertIsArray($result);
  $this->assertArrayHasKey('actions', $result);
}

/**
 * Tests validateForm with invalid data.
 *
 * @covers ::validateForm
 */
public function testValidateFormInvalidData(): void {
  $form = [];
  $form_state = new FormState();
  $form_state->setValues(['field' => '']);

  $this->form->validateForm($form, $form_state);

  $this->assertTrue($form_state->hasAnyErrors());
}
```

### Common Mock Patterns

```php
// Config Factory.
$config = $this->createMock(ImmutableConfig::class);
$config->method('get')
  ->willReturnCallback(fn(string $key) => $values[$key] ?? NULL);
$this->configFactory->method('get')
  ->with('module.settings')
  ->willReturn($config);

// Entity Query.
$query = $this->createMock(QueryInterface::class);
$query->method('accessCheck')->willReturnSelf();
$query->method('condition')->willReturnSelf();
$query->method('execute')->willReturn(['id1', 'id2']);
$storage = $this->createMock(EntityStorageInterface::class);
$storage->method('getQuery')->willReturn($query);
$this->entityTypeManager->method('getStorage')->willReturn($storage);

// Logger.
$this->logger = $this->createMock(LoggerInterface::class);
// Assert logging was called:
$this->logger->expects($this->once())
  ->method('error')
  ->with($this->stringContains('failed'));

// String translation (from UnitTestCase).
// Already available via $this->getStringTranslationStub()
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

### If adding tests causes regressions in existing tests
1. Run `git diff` to see what changed
2. Revert the problematic file
3. Re-approach with smaller incremental changes
4. NEVER leave the test suite in a broken state

### If a class is untestable as a unit test
- If it requires database access -> skip, document as "needs kernel test"
- If it extends a complex base class that can't be mocked -> skip, create Beads task
- If constructor requires Drupal bootstrap -> skip, document reason
- ONLY skip truly untestable classes — most Drupal services ARE unit-testable with proper mocking

## Verification Commands

```bash
# Primary: Audit module PHPUnit check
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpunit --format=json
# Check summary.errors = 0 AND summary.warnings = 0

# Run all unit tests for a specific module
docker exec $WEB_CONTAINER ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom/MODULE_NAME/tests/ --no-progress

# Verify new test files pass coding standards
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpcs --filter="module:MODULE_NAME" --format=json

# Verify no PHPStan errors introduced
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpstan --filter="module:MODULE_NAME" --format=json

# Clear cache (if any module code was modified to fix bugs found by tests)
docker exec $WEB_CONTAINER ./vendor/bin/drush cr
```

## Success Criteria

The task is complete when:

1. `drush audit:run phpunit --format=json` returns `summary.errors: 0`
2. `drush audit:run phpunit --format=json` returns `summary.warnings: 0`
3. All new tests pass with 0 errors and 0 failures
4. All test files pass PHPCS (Drupal + DrupalPractice standards)
5. `drush audit:run phpstan --format=json` still passes (no regressions)
6. Every custom module has at least one unit test class
7. Test classes follow all Drupal community standards listed above

## If Blocked

- If a module has no testable classes (only .module hooks) -> create a test for hook logic by extracting to a service first, or skip and document
- If the audit module phpunit analyzer is not installed -> fall back to running `./vendor/bin/phpunit` directly and manually checking for untested modules
- If a test requires kernel-level setup (database, entity storage) -> skip it, this Ralph loop is unit tests ONLY
- If fixing a failing test requires changing a public API -> create Beads task, skip that test
- If test coverage measurement requires Xdebug/PCOV and it's not available -> focus on test existence and passing status, skip coverage percentage checks
