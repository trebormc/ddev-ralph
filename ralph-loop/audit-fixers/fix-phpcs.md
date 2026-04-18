<!-- #ddev-generated -->
# Fix All PHPCS Coding Standards Violations via Audit Module

## Objective

Automatically fix all Drupal coding standards violations (PHPCS errors and warnings) reported by `drush audit:run phpcs` across all custom modules and themes. First attempt auto-fix with PHPCBF, then manually fix remaining issues iteratively until the audit reports zero errors and zero warnings.

## Requirements

### Core Loop

1. Run `drush audit:run phpcs --format=json` to get the full list of violations
2. Attempt auto-fix with PHPCBF first (fixes ~60-70% of issues automatically)
3. Re-run the audit to see what remains
4. Parse remaining `findings` — fix errors first, then warnings
5. Group findings by file for efficient fixing
6. Fix a batch of issues (up to 10 files per iteration)
7. Re-run the audit to verify fixes and detect any new issues
8. Repeat until `summary.errors` is **0** AND `summary.warnings` is **0**

### Fix Strategy

- **Step 1 — Auto-fix**: Run PHPCBF to automatically fix formatting issues
- **Step 2 — Manual fixes**: Address remaining violations that PHPCBF cannot fix:
  - Missing/wrong doc blocks: Add proper PHPDoc comments
  - Naming conventions: Fix method/variable naming to camelCase
  - Line length: Break long lines appropriately
  - Missing strict types: Add `declare(strict_types=1)`
  - Use statements ordering: Sort alphabetically
  - Missing `@throws` annotations: Document thrown exceptions
  - Array syntax: Use short array syntax `[]`
  - Spacing issues: Fix indentation (2 spaces for Drupal)

### What NOT to Fix

- Do NOT modify contrib modules — only fix custom code
- Do NOT disable PHPCS rules via `phpcs:ignore` unless truly unavoidable
- Do NOT change the coding standard (must be Drupal + DrupalPractice)
- Do NOT sacrifice code readability for standard compliance

## Technical Constraints

- All commands via `ssh web`
- Use `$DDEV_DOCROOT` for paths
- Drupal coding standard: 2-space indentation, no tabs
- Standards: Drupal + DrupalPractice (both must pass)
- Preserve all existing functionality — cosmetic changes only

## Audit Commands

```bash
# Auto-fix first (ALWAYS run this before manual fixing)
ssh web ./vendor/bin/phpcbf \
  --standard=Drupal,DrupalPractice \
  --extensions=php,module,inc,install,test,profile,theme \
  $DDEV_DOCROOT/modules/custom $DDEV_DOCROOT/themes/custom

# Full scan via Audit module
ssh web ./vendor/bin/drush audit:run phpcs --format=json

# Filtered by specific module
ssh web ./vendor/bin/drush audit:run phpcs --filter="module:MODULE_NAME" --format=json

# Only errors (skip warnings for first pass)
ssh web ./vendor/bin/drush audit:run phpcs --filter="severity:error" --format=json

# See which modules have issues
ssh web ./vendor/bin/drush audit:filters phpcs --format=json
```

## Development Approach

### Phase 1: Auto-fix

1. Run PHPCBF on all custom code
2. Run audit to see remaining issues
3. If `summary.errors: 0` and `summary.warnings: 0` -> done

### Phase 2: Fix Errors

1. Parse remaining findings with `severity: "error"`
2. Read each file, understand the violation
3. Fix the code following Drupal coding standards
4. After fixing a batch, re-run the audit
5. Repeat until `summary.errors: 0`

### Phase 3: Fix Warnings

1. Parse remaining findings with `severity: "warning"`
2. Fix doc blocks, naming conventions, etc.
3. After fixing a batch, re-run the audit
4. Repeat until `summary.warnings: 0`

### Priority Order

1. Auto-fix everything possible with PHPCBF
2. Fix errors in .module and .install files first
3. Then fix src/ PHP classes
4. Then fix test files
5. Then fix .theme files

## Verification Commands

```bash
# Primary: Audit module
ssh web ./vendor/bin/drush audit:run phpcs --format=json
# Check summary.errors = 0 AND summary.warnings = 0

# Secondary: Direct PHPCS
ssh web ./vendor/bin/phpcs \
  --standard=Drupal,DrupalPractice \
  --extensions=php,module,inc,install,test,profile,theme \
  $DDEV_DOCROOT/modules/custom $DDEV_DOCROOT/themes/custom

# After all fixes: verify PHPStan still passes
ssh web ./vendor/bin/drush audit:run phpstan --format=json
```

## Success Criteria

The task is complete when:

1. `drush audit:run phpcs --format=json` returns `summary.errors: 0`
2. `drush audit:run phpcs --format=json` returns `summary.warnings: 0`
3. No `phpcs:ignore` annotations were added (or each is documented with reason)
4. `drush audit:run phpstan --format=json` still passes (fixes didn't break types)
5. `ssh web ./vendor/bin/drush cr` runs without errors

## If Blocked

- If a PHPCS rule conflicts with PHPStan requirements -> prioritize PHPStan, suppress PHPCS with documented reason
- If a violation is in auto-generated code -> skip it, create Beads task
- If the audit module is not installed -> fall back to `./vendor/bin/phpcs` directly
- If PHPCBF breaks functionality -> revert and fix manually
