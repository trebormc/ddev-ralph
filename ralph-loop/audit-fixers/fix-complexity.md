<!-- #ddev-generated -->
# Fix All Code Complexity Issues via Audit Module

## Objective

Automatically fix all code complexity issues (high cyclomatic complexity, long methods, deep nesting) reported by `drush audit:run complexity` across all custom modules and themes. Refactor complex code into smaller, more maintainable functions iteratively until the audit reports zero errors and zero warnings.

## Requirements

### Core Loop

1. Run `drush audit:run complexity --format=json` to get the full list of issues
2. Parse the JSON output — focus on `findings` sorted by `severity`
3. Fix the highest-severity issues first (most complex methods)
4. Refactor one method/class at a time to avoid introducing bugs
5. Re-run the audit to verify fixes and check for new issues
6. Repeat until `summary.errors` is **0** and `summary.warnings` is **0**

### Refactoring Strategy

- **High cyclomatic complexity** (too many branches):
  - Extract complex conditions into named boolean methods
  - Use early returns to reduce nesting
  - Replace switch/if chains with strategy pattern or mapping arrays
  - Split method into smaller focused methods

- **Long methods** (too many lines):
  - Identify logical blocks within the method
  - Extract each block into a private method with descriptive name
  - Keep each method doing ONE thing

- **Deep nesting** (too many indentation levels):
  - Use guard clauses (early return for edge cases)
  - Invert conditions to reduce nesting
  - Extract nested loops into separate methods

- **Too many parameters**:
  - Group related parameters into value objects or arrays
  - Use builder pattern for complex configurations
  - Consider if the method is doing too much

### What NOT to Fix

- Do NOT modify contrib modules — only refactor custom code
- Do NOT change public API signatures without checking all callers
- Do NOT optimize prematurely — focus on readability
- Do NOT break existing tests — run PHPUnit after each refactor
- Do NOT change behavior — refactoring is structure only, same inputs -> same outputs

## Technical Constraints

- All commands via `docker exec $WEB_CONTAINER`
- Use `$DDEV_DOCROOT` for paths
- `declare(strict_types=1)` on all PHP files
- Maintain dependency injection patterns
- All extracted methods must have proper type hints
- Preserve all existing PHPDoc blocks and add new ones for new methods
- 2-space indentation (Drupal standard)

## Audit Commands

```bash
# Full complexity scan
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run complexity --format=json

# Filtered by specific module
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run complexity --filter="module:MODULE_NAME" --format=json

# See which modules have issues
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:filters complexity --format=json
```

## Development Approach

### Per-Method Refactoring Workflow

1. Read the method flagged by the audit
2. Understand what it does — trace inputs and outputs
3. Identify logical blocks or branch clusters
4. Extract blocks into private methods with descriptive names
5. Replace the original code with calls to the new methods
6. Verify behavior is unchanged (run PHPUnit if tests exist)
7. Re-run complexity audit to confirm the fix
8. Run PHPCS and PHPStan to ensure no new violations

### Priority Order

1. Methods with `severity: "error"` (critical complexity)
2. Service classes (most reused code)
3. Controllers and form classes
4. Plugin classes (blocks, fields)
5. Methods with `severity: "warning"` (moderate complexity)

### Example Refactoring

**Before** (cyclomatic complexity 12):
```php
public function process(array $data): array {
  if (empty($data)) { return []; }
  $results = [];
  foreach ($data as $item) {
    if ($item['type'] === 'A') {
      if ($item['status'] === 'active') {
        // 20 lines of logic...
      } else {
        // 15 lines of logic...
      }
    } elseif ($item['type'] === 'B') {
      // 25 lines of logic...
    }
  }
  return $results;
}
```

**After** (cyclomatic complexity 3):
```php
public function process(array $data): array {
  if (empty($data)) { return []; }
  $results = [];
  foreach ($data as $item) {
    $results[] = $this->processItem($item);
  }
  return array_filter($results);
}

private function processItem(array $item): ?array {
  return match($item['type']) {
    'A' => $this->processTypeA($item),
    'B' => $this->processTypeB($item),
    default => NULL,
  };
}
```

## Verification Commands

```bash
# Primary: Audit module complexity check
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run complexity --format=json
# Check summary.errors = 0 AND summary.warnings = 0

# Verify no regressions in other audits
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpstan --format=json
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpcs --format=json

# Run tests to verify behavior unchanged
docker exec $WEB_CONTAINER ./vendor/bin/phpunit $DDEV_DOCROOT/modules/custom

# Clear cache
docker exec $WEB_CONTAINER ./vendor/bin/drush cr
```

## Success Criteria

The task is complete when:

1. `drush audit:run complexity --format=json` returns `summary.errors: 0`
2. `drush audit:run complexity --format=json` returns `summary.warnings: 0`
3. All existing PHPUnit tests still pass
4. `drush audit:run phpstan --format=json` still returns `summary.errors: 0`
5. `drush audit:run phpcs --format=json` still returns `summary.errors: 0`
6. No behavior changes — only structural refactoring

## If Blocked

- If a complex method has no tests -> write a basic test BEFORE refactoring, then refactor
- If refactoring would change a public API -> create Beads task, skip that method
- If complexity is inherent (e.g., migration mapping) -> document with comment and skip
- If the audit module is not installed -> report to user, cannot proceed without it
