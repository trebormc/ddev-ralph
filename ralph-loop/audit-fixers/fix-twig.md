# Fix All Twig Template Issues via Audit Module

## Objective

Automatically fix all Twig template quality issues reported by `drush audit:run twig` across all custom modules and themes. Address security issues (raw filter abuse), cache bubbling problems, render array drilling, accessibility issues, and best practice violations iteratively until the audit reports zero errors and zero warnings.

## Requirements

### Core Loop

1. Run `drush audit:run twig --format=json` to get the full list of issues
2. Parse the JSON output — fix `severity: "error"` first (often security-related)
3. Fix issues one template at a time to avoid context switching
4. Re-run the audit to verify fixes and detect any new issues
5. Repeat until `summary.errors` is **0** and `summary.warnings` is **0**

### Fix Strategy

- **`|raw` filter abuse** (SECURITY):
  - Remove `|raw` unless the variable is explicitly sanitized
  - Use `{{ variable }}` (auto-escaped) instead of `{{ variable|raw }}`
  - If `|raw` is needed, ensure the source is trusted and add a comment explaining why

- **Render array drilling** (CACHE BREAKING):
  - Replace `{{ content.field_image[0]['#markup'] }}` with `{{ content.field_image }}`
  - Use `{{ content|without('field_x', 'field_y') }}` to exclude fields
  - Never access `['#item']`, `['#markup']`, or array indices in render arrays

- **Missing cache metadata**:
  - Ensure templates render full field objects (not drilled values)
  - If preprocess adds variables, ensure `#cache` metadata is set in the preprocess function
  - Move data extraction to preprocess hooks, not Twig

- **Business logic in templates**:
  - Move conditional logic to preprocess functions in `.theme` file
  - Templates should only handle presentation
  - Replace complex `{% if %}` chains with preprocess-computed boolean variables

- **Accessibility issues**:
  - Add `alt` attributes to `<img>` tags
  - Use semantic HTML elements (`<nav>`, `<main>`, `<article>`)
  - Ensure proper heading hierarchy
  - Add ARIA labels where needed

- **Missing `|t` filter**:
  - All user-facing strings must use `{{ 'Text'|t }}`
  - Not needed for variable content, only hardcoded strings

### What NOT to Fix

- Do NOT modify contrib module templates — only fix custom templates
- Do NOT move templates between directories without updating theme registry
- Do NOT add `dump()`, `kint()`, or any debug functions
- Do NOT change template suggestion names (file naming)

## Technical Constraints

- All commands via `docker exec $WEB_CONTAINER`
- Use `$DDEV_DOCROOT` for paths
- Templates must work with Drupal's render system and cache
- Any logic moved to preprocess must go in the `.theme` file
- Clear cache after every template change: `docker exec $WEB_CONTAINER ./vendor/bin/drush cr`
- Preprocess functions must include proper cache metadata

## Audit Commands

```bash
# Full Twig scan
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run twig --format=json

# Filtered by specific module/theme
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run twig --filter="module:THEME_NAME" --format=json

# Only security issues
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run twig --filter="severity:error,category:security" --format=json

# See which modules/themes have issues
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:filters twig --format=json
```

## Development Approach

### Per-Template Workflow

1. Read the template file flagged by the audit
2. Read the corresponding preprocess function (if exists) in `.theme` or `.module`
3. Understand what data the template needs
4. Fix the issue:
   - For render array drilling -> render the full field
   - For `|raw` abuse -> remove or justify
   - For business logic -> move to preprocess, pass as variable
5. Clear cache: `docker exec $WEB_CONTAINER ./vendor/bin/drush cr`
6. Re-run the audit filtered by that module/theme
7. Continue to next template

### Priority Order

1. Security issues (`|raw` filter abuse) — highest risk
2. Cache-breaking patterns (render array drilling) — causes stale content
3. Business logic in templates — maintainability
4. Accessibility issues — compliance
5. Best practice warnings — code quality

### Example Fixes

**Render array drilling (WRONG -> RIGHT):**
```twig
{# WRONG: Breaks cache bubbling #}
{{ content.field_image[0]['#item'].entity.uri.value }}

{# RIGHT: Full render preserves cache metadata #}
{{ content.field_image }}
```

**Logic in template (WRONG -> RIGHT):**
```twig
{# WRONG: Business logic in Twig #}
{% if node.field_date.value|date('U') > "now"|date('U') %}
  <span class="upcoming">{{ 'Upcoming'|t }}</span>
{% endif %}

{# RIGHT: Use preprocess variable #}
{% if is_upcoming %}
  <span class="upcoming">{{ 'Upcoming'|t }}</span>
{% endif %}
```

With corresponding preprocess:
```php
function mytheme_preprocess_node(array &$variables): void {
  $node = $variables['node'];
  $variables['is_upcoming'] = $node->get('field_date')->value > date('Y-m-d');
}
```

## Verification Commands

```bash
# Primary: Audit module Twig check
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run twig --format=json
# Check summary.errors = 0 AND summary.warnings = 0

# Clear cache (REQUIRED after every template change)
docker exec $WEB_CONTAINER ./vendor/bin/drush cr

# Verify no regressions in other audits
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpcs --format=json

# If preprocess functions were modified, check PHPStan
docker exec $WEB_CONTAINER ./vendor/bin/drush audit:run phpstan --format=json
```

## Success Criteria

The task is complete when:

1. `drush audit:run twig --format=json` returns `summary.errors: 0`
2. `drush audit:run twig --format=json` returns `summary.warnings: 0`
3. No `|raw` filters without documented justification
4. No render array drilling patterns remain
5. All user-facing strings use `|t` filter
6. `drush audit:run phpcs --format=json` still passes (if preprocess was modified)
7. `drush audit:run phpstan --format=json` still passes (if preprocess was modified)
8. `docker exec $WEB_CONTAINER ./vendor/bin/drush cr` runs without errors

## If Blocked

- If a `|raw` is truly needed (e.g., rendering safe markup from a WYSIWYG field) -> keep it with a Twig comment: `{# |raw justified: field output is sanitized by text format #}`
- If fixing a template requires contrib module template override -> create Beads task, skip
- If business logic is too complex to move to preprocess -> simplify in preprocess, use multiple boolean variables
- If the audit module is not installed -> report to user, cannot proceed without it
