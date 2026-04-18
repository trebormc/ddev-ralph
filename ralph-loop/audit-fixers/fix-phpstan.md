<!-- #ddev-generated -->
# Fix All PHPStan Errors via Audit Module

## Objective

Automatically fix all PHPStan static analysis errors reported by `drush audit:run phpstan` across all custom modules and themes. Work in batches, fixing issues iteratively until the audit reports zero errors.

## Requirements

### Core Loop

1. Run `drush audit:run phpstan --format=json` to get the full list of issues
2. Parse the JSON output — focus on `findings` with `severity: "error"`
3. Group findings by file for efficient fixing
4. Fix the first batch of errors (up to 10 files per iteration)
5. Re-run the audit to verify fixes and detect any new issues
6. Repeat until `summary.errors` is **0**
7. After errors are clean, address `severity: "warning"` items if any remain

### Fix Strategy

- **Type errors**: Add proper type hints, fix parameter types, add return types
- **Undefined methods/properties**: Fix typos, add missing methods, update interfaces
- **Deprecations**: Replace deprecated API calls with current equivalents
- **Access issues**: Add proper `accessCheck(TRUE)` on entity queries
- **Missing imports**: Add `use` statements for referenced classes
- **Null safety**: Add null checks where PHPStan reports possible null access

### What NOT to Fix

- Do NOT modify contrib modules — only fix custom code
- Do NOT suppress errors with `@phpstan-ignore` unless truly unavoidable (document why)
- Do NOT change the PHPStan level (must remain level 8)
- Do NOT modify test files to suppress errors — fix the actual code

## Technical Constraints

- All commands via `ssh web`
- Use `$DDEV_DOCROOT` for paths (detect with `grep "^docroot:" .ddev/config.yaml`)
- `declare(strict_types=1)` on all PHP files
- Maintain Drupal coding standards while fixing (don't break PHPCS to fix PHPStan)
- Dependency injection — never introduce `\Drupal::service()` static calls

## Audit Command

```bash
# Full scan (all custom modules and themes)
ssh web drush audit:run phpstan --format=json

# Filtered by specific module (use after identifying which modules have issues)
ssh web drush audit:run phpstan --filter="module:MODULE_NAME" --format=json

# See which modules have issues
ssh web drush audit:filters phpstan --format=json
```

## Development Approach

### Per-Iteration Workflow

1. Run the audit command and capture JSON output
2. Parse `summary.errors` — if 0, move to warnings or finish
3. Read the files listed in `findings[].file` at `findings[].line`
4. Understand the context of each error from `findings[].message`
5. Fix the code — apply the minimum change needed
6. After fixing a batch, re-run the audit
7. If new errors appeared from the fixes, fix those too
8. Continue until the audit is clean

### Priority Order

1. Fix errors in services and controllers first (most impactful)
2. Then fix plugin classes (blocks, fields, etc.)
3. Then fix form classes
4. Then fix event subscribers and other support classes
5. Address warnings last

## Verification Commands

```bash
# Primary: Audit module
ssh web drush audit:run phpstan --format=json
# Check summary.errors = 0

# Secondary: Direct PHPStan (confirms audit results)
ssh web ./vendor/bin/phpstan analyse $DDEV_DOCROOT/modules/custom --level=8

# After all fixes: run PHPCS to ensure fixes didn't break coding standards
ssh web drush audit:run phpcs --format=json
```

## Success Criteria

The task is complete when:

1. `drush audit:run phpstan --format=json` returns `summary.errors: 0`
2. `drush audit:run phpstan --format=json` returns `summary.warnings: 0` (or only non-actionable warnings)
3. No `@phpstan-ignore` annotations were added (or each is documented with reason)
4. `drush audit:run phpcs --format=json` still returns `summary.errors: 0` (fixes didn't break standards)
5. `ssh web drush cr` runs without errors

## If Blocked

- If a PHPStan error requires changes to contrib module code -> create a Beads task documenting the issue, skip it
- If fixing an error introduces a new error in another file -> fix both before re-running
- If an error is genuinely unfixable (framework limitation) -> document with `@phpstan-ignore-next-line` and add a comment explaining why
- If the audit module is not installed -> fall back to `./vendor/bin/phpstan analyse` directly
