# AI Coding Agent Guide

Project-specific instructions for AI agents. MUST be loaded at conversation start.

## Default Mode
- Architect mode enabled by default: detailed analysis, patterns, trade-offs, architectural guidance
- Stop and ask for context if unable to write code meeting guidelines

## Development Rules
Discourse is large with long history. Understand context before changes.

### All Files
- Always lint changed files
- Make display strings translatable (use placeholders, not split strings)
- Create subagent to review changes against this file after completing tasks

### Toolset
- Use `pnpm` for JavaScript, `bundle` for Ruby
- Use helpers in bin over bundle exec (bin/rspec, bin/rake)

### JavaScript
- No empty backing classes for template-only components unless requested
- Use FormKit for forms: https://meta.discourse.org/t/discourse-toolkit-to-render-forms/326439 (`app/assets/javascripts/discourse/app/form-kit`)

### JSDoc
- Required for classes, methods, members (except `@service` members, constructors)
- Multiline format only
- Components: `@component` name, list params (`this.args` or `@paramname`)
- Methods: no `@returns` for `@action`, use `@returns` for getters (not `@type`)
- Members: specify `@type`

## Testing
- Do not write unnecessary comments in tests, every single assertion doesn't need a comment
- Don't test functionality handled by other classes/components
- Don't write obvious tests
- Ruby: use `fab!()` over `let()`, system tests for UI (`spec/system`), use page objects for system spec finders (`spec/system/page_objects`)

### Page Objects (System Specs)
- Located in `spec/system/page_objects/pages/`, inherit from `PageObjects::Pages::Base`
- NEVER store `find()` results - causes stale element references after re-renders
- Use `has_x?` / `has_no_x?` patterns for state checks (finds fresh each time)
- Action methods find+interact atomically, return `self` for chaining
- Don't assert immediate UI feedback after clicks (tests browser, not app logic)

### Commands
```bash
# Ruby tests
bin/rspec [spec/path/file_spec.rb[:123]]
LOAD_PLUGINS=1 bin/rspec  # Plugin tests

# JavaScript tests
bin/rake qunit:test # RUN all non plugin tests
LOAD_PLUGINS=1 TARGET=all FILTER='fill filter here' bin/rake qunit:test # RUN specific tests based on filter

Exmaple filters JavaScript tests:

  emoji-test.js
    ...
    acceptance("Emoji" ..
      test("cooked correctly")
    ...
  Filter string is: "Acceptance: Emoji: cooked correctly"

  user-test.js
    ...
    module("Unit | Model | user" ..
      test("staff")
    ...
  Filter string is: "Unit | Model | user: staff"

# Linting
bin/lint path/to/file path/to/another/file
bin/lint --fix path/to/file path/to/another/file
bin/lint --fix --recent # Lint all recently changed files
```

ALWAYS lint any changes you make

## Site Settings
- Configured in `config/site_settings.yml` or `config/settings.yml` for plugins
- Functionality in `lib/site_setting_extension.rb`
- Access: `SiteSetting.setting_name` (Ruby), `siteSettings.setting_name` (JS with `@service siteSettings`)

## Services
- Extract business logic (validation, models, permissions) from controllers
- https://meta.discourse.org/t/using-service-objects-in-discourse/333641
- Examples: `app/services` (only classes with `Service::Base`)

## Database & Performance
- ActiveRecord: use `includes()`/`preload()` (N+1), `find_each()`/`in_batches()` (large sets), `update_all`/`delete_all` (bulk), `exists?` over `present?`
- Migrations: rollback logic, `algorithm: :concurrently` for large tables, deprecate before removing columns
- Queries: use `explain`, specify columns, strategic indexing, `counter_cache` for counts

## Custom Fields
**CRITICAL**: Discourse stores custom fields in separate tables, NOT as JSONB columns

### Architecture
- Custom fields stored in `post_custom_fields`, `topic_custom_fields`, `user_custom_fields`, etc.
- The `custom_fields` attribute on models is a **virtual accessor** that joins to these tables
- No `custom_fields` column exists on main tables (`posts`, `topics`, etc.)

### Querying Custom Fields
```ruby
# ❌ WRONG - This will cause 500 errors
Post.where("custom_fields @> ?", { my_field: true }.to_json)

# ✅ CORRECT - Load records first, filter in Ruby
all_posts = Post.where(topic_id: topic_id)
filtered = all_posts.select { |post| post.custom_fields["my_field"] == true }

# ✅ ALTERNATIVE - Use joins (more efficient for large datasets)
Post.joins(:_custom_fields)
    .where(topic_id: topic_id)
    .where(post_custom_fields: { name: "my_field", value: "t" })
```

### Registration & Serialization
```ruby
# In plugin.rb after_initialize block
register_post_custom_field_type("field_name", :boolean)

add_to_serializer(:post, :field_name) do
  object.custom_fields["field_name"] == true
end
```

## HTTP Response Codes
- **204 No Content**: Use `head :no_content` for successful operations that don't return data
  - DELETE operations that successfully remove a resource
  - UPDATE/PUT operations that succeed but don't need to return modified data
  - POST operations that perform an action without creating/returning resources (mark as read, clear notifications)
- **200 OK**: Use `render json: success_json` when returning confirmation data or when clients expect a response body
- **201 Created**: Use when creating resources, include location header or resource data
- **Do NOT use 204 when**:
  - Creating resources (use 201 with data)
  - Returning modified/useful data to the client
  - Clients expect confirmation data beyond success/failure

## Security
- XSS: use `{{}}` (escaped) not `{{{ }}}`, sanitize with `sanitize`/`cook`, no `innerHTML`, careful with `@html`
- Auth: Guardian classes (`lib/guardian.rb`), POST/PUT/DELETE for state changes, CSRF tokens, `protect_from_forgery`
- Input: validate client+server, strong parameters, length limits, don't trust client-only validation
- Authorization: Guardian classes, route+action permissions, scope limiting, `can_see?`/`can_edit?` patterns

## Decorating Posts with Glimmer Components

To add Glimmer components to post content, use `helper.renderGlimmer()` within `api.decorateCookedElement()`. This is the modern Discourse pattern for enhancing posts.

### Pattern (following discourse-footnote plugin)
```javascript
// In a .gjs initializer file
import { apiInitializer } from "discourse/lib/api";
import MyComponent from "../components/my-component";

export default apiInitializer((api) => {
  api.decorateCookedElement(
    (element, helper) => {
      const post = helper.getModel();

      // Check conditions
      if (!post || !post.custom_field) {
        return;
      }

      // Create container
      const container = document.createElement("div");
      container.className = "my-component-container";
      element.appendChild(container);

      // Render component with data
      helper.renderGlimmer(container, MyComponent, {
        post,
        // other data
      });
    },
    { onlyStream: true }
  );
});
```

### Component receives data via `this.args.data`
```javascript
// In component class
async loadData() {
  const post = this.args.data.post;
  // use post data
}

// In template
<template>
  <div>{{@data.post.id}}</div>
</template>
```

### References
- Example: `assets/javascripts/discourse/initializers/lottery-intro-summary.gjs`
- Discourse footnote plugin: `/Users/hans/Development/vzekc/discourse/plugins/footnote/assets/javascripts/api-initializers/inline-footnotes.gjs`
- Discourse poll plugin: `/Users/hans/Development/vzekc/discourse/plugins/poll/assets/javascripts/discourse/initializers/extend-for-poll.gjs`

## Knowledge Sharing
- ALWAYS persist information for ALL developers (no conversational-only memory)
- Follow project conventions, prevent knowledge silos
- Recommend storage locations by info type
- Inform when this file changes and reloads
