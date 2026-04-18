<!-- #ddev-generated -->
# Generate Behat Tests for Drupal Project

## Objective

Generate Behat acceptance tests (Gherkin feature files) for a Drupal project that already uses Behat. Tests should cover critical user flows, content management operations, permission-based access, and configuration management. Written in natural language so that non-technical stakeholders can read and validate them.

**Reference skill**: `drupal-behat-test` — load it for templates, step definitions, and patterns.

**PREREQUISITE**: This prompt should ONLY be used when the project has `behat.yml` or `behat.yml.dist`. If Behat is not installed, skip this prompt entirely.

## Requirements

### Pre-Check (Planning Phase)

Before creating any tasks, verify Behat is installed:

```bash
# Check for Behat config
ssh web test -f behat.yml && echo "behat.yml found" || echo "no behat.yml"
ssh web test -f behat.yml.dist && echo "behat.yml.dist found" || echo "no behat.yml.dist"

# Check Behat binary
ssh web test -f ./vendor/bin/behat && echo "behat installed" || echo "behat not installed"

# List existing features
find . -name "*.feature" -path "*/behat/*" 2>/dev/null || find . -name "*.feature" -path "*/features/*" 2>/dev/null

# List available step definitions
ssh web ./vendor/bin/behat --definitions 2>/dev/null | head -50
```

If Behat is NOT installed, **do not proceed**. Create a single Beads task: "Install Behat: `composer require --dev drupal/drupal-extension behat/mink-selenium2-driver`" and close it with a note.

### Core Loop

1. Identify critical user flows from the project's custom modules:
   - Content creation, editing, deletion for each content type
   - User registration and login flows
   - Admin configuration forms
   - Permission-based access (admin vs editor vs anonymous)
   - Custom module functionality exposed via routes
2. Check existing `.feature` files — adapt style and avoid duplication
3. Read the existing `FeatureContext.php` — understand available custom steps
4. Generate `.feature` files following Gherkin best practices
5. Generate custom step definitions if needed (in `FeatureContext.php`)
6. Run `behat --dry-run` to verify syntax
7. Run behat to verify scenarios pass
8. Repeat until all critical flows have acceptance tests

### Feature File Structure

```
tests/behat/features/
├── content/
│   ├── article.feature
│   ├── page.feature
│   └── media.feature
├── auth/
│   ├── login.feature
│   └── permissions.feature
├── admin/
│   └── module_config.feature
└── custom/
    └── MODULE_feature.feature
```

### Writing Good Gherkin

**Business language, not implementation details:**
```gherkin
# GOOD - describes behavior
Scenario: Editor creates article
  Given I am logged in as a user with the "editor" role
  When I create an article titled "Breaking News"
  Then I should see "has been created"

# BAD - describes implementation
Scenario: Test node add form
  Given I am on "node/add/article"
  When I fill in "edit-title-0-value" with "Breaking News"
  And I click "#edit-submit"
```

**Use Background for shared setup:**
```gherkin
Background:
  Given I am logged in as a user with the "editor" role

Scenario: Create article
  ...

Scenario: Edit article
  ...
```

**Use @api tag for content creation via API** (faster than UI):
```gherkin
@api
Scenario: Edit existing article
  Given "article" content:
    | title          | status |
    | Existing Post  | 1      |
  When I am on the edit page of "article" content "Existing Post"
```

### Tags Convention

```gherkin
@api          # Uses Drupal API driver (faster content creation)
@javascript   # Requires Selenium/Chrome (real browser)
@smoke        # Quick critical path tests
@content      # Content management tests
@auth         # Authentication and permissions
@config       # Configuration management
@MODULE       # Tests for a specific module
@wip          # Work in progress (exclude from CI)
```

### Scenarios to Generate

For each custom module, generate scenarios covering:

1. **Content types** (if module defines them):
   - Create content as authorized user
   - Edit existing content
   - Delete content
   - Verify anonymous cannot access restricted content

2. **Configuration forms**:
   - Admin saves configuration successfully
   - Validation catches invalid input
   - Non-admin gets 403

3. **Permissions**:
   - Each custom permission tested with authorized and unauthorized users
   - Admin access verified
   - Anonymous access restrictions

4. **Custom functionality**:
   - Any routes exposed by the module
   - API endpoints (if applicable)
   - Custom blocks appearing correctly

### Custom Step Definitions

If the existing steps are not sufficient, add new ones to `FeatureContext.php`:

```php
/**
 * @Given I am on the edit page of :type content :title
 */
public function iAmOnEditPageOfContent(string $type, string $title): void {
  $node = \Drupal::entityTypeManager()
    ->getStorage('node')
    ->loadByProperties(['title' => $title, 'type' => $type]);
  $node = reset($node);
  if (!$node) {
    throw new \Exception("No $type node found with title '$title'");
  }
  $this->visitPath('/node/' . $node->id() . '/edit');
}
```

**Rules for custom steps:**
- Keep steps reusable across features
- Use type-hinted parameters
- Throw descriptive exceptions on failure
- Document with proper PHPDoc `@Given/@When/@Then` annotations

### What NOT to Do

- Do NOT write overly specific steps tied to CSS selectors
- Do NOT use `@javascript` when Goutte/BrowserKit suffices (much faster)
- Do NOT duplicate steps that Drupal Extension already provides
- Do NOT write features for contrib module functionality
- Do NOT put business logic in feature files — logic goes in FeatureContext
- Do NOT repeat Background steps in individual scenarios
- Do NOT create steps with hidden side effects

## Technical Constraints

- All commands via `ssh web`
- Behat config: `behat.yml` or `behat.yml.dist`
- Drupal Extension `^5` for D10/D11
- Feature files in English
- Step definitions in `FeatureContext.php`
- Use `@api` driver for content creation (faster than UI)
- Use `@javascript` only when JS is required

## Execution Commands

```bash
# Verify syntax (dry run)
ssh web ./vendor/bin/behat --dry-run --config=behat.yml

# Run all tests
ssh web ./vendor/bin/behat --config=behat.yml

# Run by tag
ssh web ./vendor/bin/behat --tags=@content
ssh web ./vendor/bin/behat --tags=@smoke
ssh web ./vendor/bin/behat --tags="@content&&~@javascript"

# Run specific feature
ssh web ./vendor/bin/behat features/content/article.feature

# Run specific scenario by line
ssh web ./vendor/bin/behat features/content/article.feature:15

# List all available steps
ssh web ./vendor/bin/behat --definitions

# Generate snippets for undefined steps
ssh web ./vendor/bin/behat --dry-run --append-snippets
```

## Success Criteria

1. Behat is installed and configured
2. All critical user flows have feature files
3. All scenarios pass: `behat --config=behat.yml` exits 0
4. Custom step definitions are reusable and well-documented
5. Feature files use business language, not implementation details
6. `@api` tag used where possible for speed
7. `@javascript` tag only where JS is genuinely required

## If Blocked

- If Behat is not installed → create task to install: `composer require --dev drupal/drupal-extension behat/mink-selenium2-driver`
- If Selenium/ChromeDriver not available → skip `@javascript` scenarios, focus on `@api` and Goutte tests
- If step definitions are missing → generate snippets with `behat --dry-run --append-snippets` then implement
- If content types do not exist → create them in Background steps using `@api` driver
- If the project has no routes to test → generate only content and permission scenarios
- If existing features have a different style → adapt to match the existing convention
