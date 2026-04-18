<!-- #ddev-generated -->
# Generate Kernel Tests for All Custom Modules

## Objective

Generate missing Kernel tests (`KernelTestBase`) for all custom modules that interact with Drupal services, entities, database, configuration, plugins, hooks, or any Drupal API. Kernel tests are the **most valuable test type** for custom Drupal modules — they test real integration with the Drupal kernel while running 10x faster than Functional tests.

**Reference skill**: `drupal-kernel-test` — load it for templates, patterns, and anti-patterns.

## Requirements

### Core Loop

1. Detect Drupal version (D10 vs D11) — affects data provider syntax and PHPUnit version
2. List all custom modules and identify classes that need Kernel tests:
   - Services (`src/Service/`) that use entity storage, database, config, or the container
   - Entity classes (`src/Entity/`) — CRUD operations
   - Plugin classes (`src/Plugin/`) — plugin managers with real discovery
   - Event subscribers (`src/EventSubscriber/`)
   - Access checkers (`src/Access/`)
   - Form submit/validate handlers (logic only, not UI rendering)
   - Queue workers, cron hooks, token replacement
3. Check existing Kernel tests — adapt style, do not duplicate
4. For each module: generate Kernel test classes covering all relevant source classes
5. Run the tests to verify they pass
6. Run PHPCS on new test files
7. Re-run audit (if available) to verify improvement
8. Repeat until all modules have adequate Kernel test coverage

### What Needs Kernel Tests (NOT Unit Tests)

Use Kernel tests when the class:
- Receives services via dependency injection that interact with Drupal (entity_type.manager, database, config.factory)
- Performs entity CRUD (create, load, update, delete)
- Runs database queries (entity queries, select queries)
- Checks access/permissions using Drupal's access system
- Dispatches or subscribes to events via the event dispatcher
- Uses the plugin manager for real plugin discovery
- Reads/writes configuration
- Implements hooks that interact with the database or entities

Do NOT use Kernel tests for:
- Pure PHP utility classes with no Drupal dependencies → Unit test
- HTML rendering verification → Functional test
- Form UI rendering → Functional test
- JavaScript/AJAX → FunctionalJavascript test

### Kernel Test Standards

**CRITICAL: PHPDoc annotations, NOT PHP 8 attributes.** Works in both Drupal 10 and 11.

```php
<?php
declare(strict_types=1);

namespace Drupal\Tests\MODULE\Kernel;

use Drupal\KernelTests\KernelTestBase;

/**
 * Tests DESCRIPTION.
 *
 * @coversDefaultClass \Drupal\MODULE\CLASS_UNDER_TEST
 * @group MODULE
 */
class ClassUnderTestTest extends KernelTestBase {

  protected static $modules = [
    'system',
    'user',
    // Only strictly necessary dependencies
    'MODULE',
  ];

  protected function setUp(): void {
    parent::setUp();
    $this->installEntitySchema('user');
    $this->installConfig(['system', 'MODULE']);
  }

}
```

### Setup Methods Reference

| Method | When to use |
|--------|-------------|
| `installEntitySchema('type')` | Before CRUD with content entities (node, user, taxonomy_term) |
| `installConfig(['module'])` | When code reads config from `config/install/` |
| `installSchema('module', ['table'])` | For custom tables from `hook_schema()` only |
| `$this->container->get('service.id')` | To get the service under test |

**DO NOT** use `installEntitySchema()` for config entities — they have no tables.
**DO NOT** use `enableModules()` in setUp() — use the `$modules` property.

### Per-Module Workflow

1. **Read all source files** in the module's `src/` directory
2. **Identify constructors** — list injected services to understand dependencies
3. **Determine required modules** — only what is strictly needed in `$modules`
4. **Write setUp()** — install entity schemas, config, and custom schemas as needed
5. **Write test methods** — one per behavior, covering:
   - Happy path (normal operation)
   - Edge cases (empty input, null, boundaries)
   - Error conditions (exceptions, invalid data)
   - Access/permission checks (if applicable)
6. **Use real entities** — create Node, User, Term etc. with `Entity::create()`
7. **Reload after save** — always `Entity::load($id)` to verify persistence
8. **Run the test file** to verify it passes

### Priority Order

1. **Modules with zero tests** — highest value
2. **Services with complex logic** — most business value
3. **Entity-related code** — CRUD, access, queries
4. **Plugin classes** — blocks, fields, formatters
5. **Event subscribers and hooks** — integration points

### What NOT to Do

- Do NOT install unnecessary modules in `$modules` — each adds setup time
- Do NOT make assertions about rendered HTML — that is Functional
- Do NOT create unnecessary fixtures — only what the test needs
- Do NOT modify contrib modules
- Do NOT skip `parent::setUp()` call
- Do NOT use `\Drupal::service()` in tests — use `$this->container->get()`
- Do NOT add `phpcs:ignore` to suppress warnings

## Technical Constraints

- All commands via `ssh web`
- Use `$DDEV_DOCROOT` for paths
- `declare(strict_types=1)` on all files
- Drupal coding standards: 2-space indentation
- Data providers must be `static` methods (D10+D11 compatible)
- Never use `withConsecutive()` (removed in PHPUnit 10)
- Prefer `assertSame()` over `assertEquals()`

## Audit Commands

```bash
# Full test audit
ssh web ./vendor/bin/drush audit:run phpunit --format=json

# Filtered by module
ssh web ./vendor/bin/drush audit:run phpunit --filter="module:MODULE_NAME" --format=json

# Run Kernel tests for a module
ssh web ./vendor/bin/phpunit -c core --testsuite kernel $DDEV_DOCROOT/modules/custom/MODULE/

# Run specific test file
ssh web ./vendor/bin/phpunit -c core $DDEV_DOCROOT/modules/custom/MODULE/tests/src/Kernel/Service/MyServiceTest.php

# PHPCS on test files
ssh web ./vendor/bin/phpcs --standard=Drupal,DrupalPractice $DDEV_DOCROOT/modules/custom/MODULE/tests/src/Kernel/
```

## Useful Core Traits

```php
use Drupal\Tests\node\Traits\NodeCreationTrait;
use Drupal\Tests\user\Traits\UserCreationTrait;
use Drupal\Tests\node\Traits\ContentTypeCreationTrait;
use Drupal\Tests\Traits\Core\CronRunTrait;
```

## Auxiliary Test Module

When you need routes, services, or config that only exist for the test:

```yaml
# tests/modules/MODULE_test/MODULE_test.info.yml
name: 'MODULE Test'
type: module
core_version_requirement: ^10 || ^11
package: Testing
dependencies:
  - MODULE:MODULE
hidden: true
```

Then add to the test: `protected static $modules = ['MODULE', 'MODULE_test'];`

## Success Criteria

1. Every custom module with services/entities/plugins has Kernel tests
2. All generated tests pass: `phpunit -c core --testsuite kernel --group MODULE` exits 0
3. All test files pass PHPCS (Drupal + DrupalPractice)
4. No regressions in existing tests
5. Each test class has `@group` and `@coversDefaultClass` annotations
6. Entity operations always reload from DB to verify persistence

## If Blocked

- If `installEntitySchema()` fails → check the entity type ID matches what is in the entity annotation
- If a service cannot be retrieved from container → verify the module is in `$modules` and `installConfig()` was called
- If tests are too slow → reduce the number of modules in `$modules` to the minimum required
- If a class requires HTTP/browser → skip it, create a Beads task for Functional test
- If a module has only `.module` hook code → extract logic to a testable service or skip
- If entity queries fail → ensure `accessCheck(TRUE)` is called on the query
