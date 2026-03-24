# Custom API Integration Module

## Objective

Create a custom Drupal 10 module that integrates with an external REST API to fetch and cache product data, displaying it as a block and providing a service for other modules.

## Requirements

### Core Functionality
- Custom service to fetch data from external API
- Configurable API endpoint and credentials via admin form
- Cache responses for 1 hour (configurable)
- Block plugin to display featured products
- Drush command to manually refresh cache

### Admin Interface
- Configuration form at /admin/config/services/product-api
- Fields: API URL, API Key, Cache TTL
- Test connection button
- Permission: "administer product api"

### Data Handling
- Fetch product list from API
- Store in Drupal cache with tags
- Handle API errors gracefully (log + fallback)
- Expose data via custom service

### Block Plugin
- "Featured Products" block
- Configurable: number of products to show (1-10)
- Responsive layout with Twig template
- Cache tags for proper invalidation

## Technical Constraints

- Drupal 10.2+ / 11 compatible
- PHP 8.1+ with strict types
- Follow Drupal coding standards (PHPCS)
- PHPStan level 8 compliance
- Dependency injection for all services
- No \Drupal::service() calls in classes
- Guzzle for HTTP requests (core service)

## Module Structure

```
web/modules/custom/product_api/
├── product_api.info.yml
├── product_api.module
├── product_api.permissions.yml
├── product_api.routing.yml
├── product_api.services.yml
├── product_api.links.menu.yml
├── config/
│   ├── install/
│   │   └── product_api.settings.yml
│   └── schema/
│       └── product_api.schema.yml
├── src/
│   ├── ProductApiServiceInterface.php
│   ├── ProductApiService.php
│   ├── Form/
│   │   └── SettingsForm.php
│   ├── Plugin/
│   │   └── Block/
│   │       └── FeaturedProductsBlock.php
│   └── Commands/
│       └── ProductApiCommands.php
├── templates/
│   └── featured-products-block.html.twig
└── tests/
    └── src/
        ├── Unit/
        │   └── ProductApiServiceTest.php
        └── Kernel/
            └── ProductApiIntegrationTest.php
```

## Development Approach

Follow TDD for each component:

1. Write failing test
2. Implement minimum code to pass
3. Refactor if needed
4. Run PHPCS and PHPStan
5. Repeat

## Phases

### Phase 1: Module Foundation
- Create module scaffolding (info.yml, services.yml)
- Implement ProductApiService with interface
- Add configuration schema
- Unit tests for service

### Phase 2: Admin Configuration
- Settings form with validation
- Permissions
- Menu link
- Kernel test for form submission

### Phase 3: Block Plugin
- FeaturedProductsBlock plugin
- Twig template
- Cache tags and contexts
- Block configuration form

### Phase 4: Drush Command
- Drush command to refresh cache
- Clear specific cache tags

### Phase 5: Quality Assurance
- PHPCS compliance check
- PHPStan level 8 analysis
- All tests passing
- Manual testing via drush and UI

## Verification Commands

```bash
# Clear cache
docker exec $WEB_CONTAINER drush cr

# Run tests
docker exec $WEB_CONTAINER ./vendor/bin/phpunit web/modules/custom/product_api

# Code standards
docker exec $WEB_CONTAINER ./vendor/bin/phpcs web/modules/custom/product_api

# Static analysis
docker exec $WEB_CONTAINER ./vendor/bin/phpstan analyse web/modules/custom/product_api --level=8

# Test drush command
docker exec $WEB_CONTAINER drush product-api:refresh
```

## Success Criteria

The module is complete when:

1. Module enables without errors: `drush en product_api -y`
2. Configuration form works at /admin/config/services/product-api
3. Block can be placed and displays products
4. Drush command refreshes cache successfully
5. All PHPUnit tests pass
6. PHPCS reports no errors
7. PHPStan level 8 reports no errors

## API Mock (for testing)

Use this mock data structure for testing:

```json
{
  "products": [
    {
      "id": 1,
      "name": "Product One",
      "price": 29.99,
      "description": "Description here",
      "image_url": "https://example.com/img/1.jpg"
    }
  ],
  "total": 100,
  "page": 1
}
```

## If Blocked

If you encounter issues:

1. Check Drupal logs: `drush watchdog:show`
2. Verify cache: `drush cr`
3. Check permissions
4. Document the blocker and what you've tried
5. If truly unrecoverable, signal ERROR
