# AI Coding Agent Guide

Project-specific instructions for AI agents. MUST be loaded at conversation start.

## Default Mode
- Architect mode enabled by default: detailed analysis, patterns, trade-offs, architectural guidance
- Stop and ask for context if unable to write code meeting guidelines

## Role Terminology

Clear role names used throughout the codebase:

- **donor** / **Spender**: Person who has hardware to give away (not in system)
- **facilitator** / **Vermittler**: User who creates donation offer, finds picker, provides donor's contact info (stored as `creator_user_id` in database)
- **picker** / **Abholer**: User who picks up donation from donor, then either keeps it (writes Erhaltungsbericht) OR creates lottery (becomes lottery owner)
- **winner** / **Gewinner**: User who wins a packet in the lottery, writes Erhaltungsbericht

**Key Points:**
- Facilitator is NOT the donor - they facilitate on behalf of the donor
- Only the picker can mark a donation as "picked up"
- Picker receives donor's contact info via PM when assigned
- Picker chooses after pickup: keep it OR create lottery (no auto-created draft)

## Development Rules
Discourse is large with long history. Understand context before changes.

### All Files
- Always lint changed files with `bundle exec rubocop -a` before committing
- Run `bundle exec rubocop plugin.rb app/ lib/ spec/` to verify main code passes
- Make display strings translatable (use placeholders, not split strings)
- Create subagent to review changes against this file after completing tasks
- **NEVER use git rebase** - repo may be pushed from multiple places, rewriting history causes conflicts

### Toolset
- Use `pnpm` for JavaScript, `bundle` for Ruby
- Use helpers in bin over bundle exec (bin/rspec, bin/rake)

### JavaScript
- No empty backing classes for template-only components unless requested
- Use FormKit for forms: https://meta.discourse.org/t/discourse-toolkit-to-render-forms/326439 (`app/assets/javascripts/discourse/app/form-kit`)
- **NEVER use console.log in production code** - remove all debug logging before committing

### Code Style Rules (CI-Enforced)

All code MUST pass these CI linters. Generate code that conforms from the start.

#### JavaScript / GJS (ESLint + Prettier)
- **Strict equality**: Always use `===`/`!==`, never `==`/`!=` (`eqeqeq`)
- **No `var`**: Use `const` or `let` (`no-var`)
- **No `console.log`**: Forbidden in production code (`no-console`)
- **No `debugger`**: Remove all debug statements (`no-debugger`)
- **No `eval()`**: Never use eval or equivalent (`no-eval`)
- **No `alert()`**: Never use alert/confirm/prompt (`no-alert`)
- **No bitwise operators**: Use explicit alternatives (`no-bitwise`)
- **No variable shadowing**: Outer scope variable names must not be reused (`no-shadow`)
- **Always use curly braces**: Even for single-line `if`/`else`/`for`/`while` (`curly`)
- **Object shorthand**: Use `{ foo }` not `{ foo: foo }` for properties (`object-shorthand`)
- **Radix parameter**: Always pass radix to `parseInt()` e.g. `parseInt(x, 10)` (`radix`)
- **No `extend` on native prototypes**: Never modify built-in prototypes (`no-extend-native`)
- **Trailing commas**: Use trailing commas in ES5 contexts (arrays, objects, params) (`trailingComma: "es5"`)
- **Import order** (enforced by `eslint-plugin-import-sort`):
  1. `@glimmer/*`, `@ember/*`, then other packages
  2. `discourse/*`, `discourse-common/*`, `admin/*`
  3. `discourse/plugins/*`
  4. Relative imports (`./`, `../`)
- **Class member order** (enforced by `eslint-plugin-sort-class-members`):
  1. Static properties/methods
  2. `@service` injections
  3. `@tracked` properties
  4. Regular properties
  5. Private properties
  6. Constructor, `init`, `willDestroy`
  7. Everything else
  8. `<template>` tag (last)
- **Blank line after imports**: Required (`discourse/line-after-imports`)
- **Blank line before default export**: Required (`discourse/line-before-default-export`)
- **Blank lines between class members**: Required (`discourse/lines-between-class-members`)
- **No `onclick` attribute**: Use Ember `{{on "click"}}` modifier (`discourse/no-onclick`)
- **No curly component invocations**: Use angle bracket `<MyComponent />` not `{{my-component}}` (`discourse/no-curly-components`)
- **Component names capitalized**: `<MyComponent />` not `<myComponent />` (`discourse/capital-components`)
- **No `this.` in `<template>` tag**: Use bare names, not `this.foo` (`discourse/template-tag-no-self-this`)
- **No `querySelector`**: Use Discourse helpers instead (`discourse/no-simple-query-selector`)
- **Use updated imports**: Follow current Discourse import paths, not deprecated ones (`discourse/deprecated-imports`, `discourse/discourse-common-imports`)
- **GJS/GTS files**: Parsed with `ember-eslint-parser`, formatted with `prettier-plugin-ember-template-tag`

#### Template Lint (Ember Templates / GJS `<template>`)
- **Strict mode required**: All `.gjs`/`.gts` templates must use strict mode (`require-strict-mode`)
- **No `{{action}}` modifier**: Use `{{on "click" this.method}}` instead (`no-action`)
- **No unnecessary curly parens/strings**: `{{@foo}}` not `{{(@foo)}}`, `@foo` not `{{"foo"}}` (`no-unnecessary-curly-parens`, `no-unnecessary-curly-strings`)
- **Simple modifiers**: Prefer built-in modifiers (`simple-modifiers`)
- **No chained `this`**: Avoid `{{this.foo.bar.baz}}` chains (`no-chained-this`)
- **No `@class`**: Use angle bracket invocation (`discourse/no-at-class`)

#### SCSS / CSS (Stylelint)
- **Standard SCSS**: Extends `stylelint-config-standard-scss`
- **Valid hex colors**: No invalid hex values (`color-no-invalid-hex`)
- **Known units only**: No unknown CSS units (`unit-no-unknown`)
- **Rule empty line before**: Always (except after single-line comment or first-nested) (`rule-empty-line-before`)
- **No redundant declaration lines**: Never put empty lines before declarations (`declaration-empty-line-before: never`)
- **No deprecated property values**: Avoid deprecated keywords like `break-word` → use `anywhere` or `break-all` (`declaration-property-value-keyword-no-deprecated`)
- **Modern color function notation**: Use `rgb(0 0 0 / 50%)` not `rgba(0, 0, 0, 0.5)` (both currently allowed but prefer modern)

#### Ruby (RuboCop + SyntaxTree)
- **rubocop-discourse** ruleset with SyntaxTree compatibility
- **No monkey patching in plugins**: Use `prepend` pattern, never `class_eval` (`Discourse/Plugins/NoMonkeyPatching`)
- **Call `requires_plugin`**: All plugin controllers must call `requires_plugin` (`Discourse/Plugins/CallRequiresPlugin`)
- **Use `plugin_instance.on`**: For event listeners in plugins (`Discourse/Plugins/UsePluginInstanceOn`)
- **Namespace methods**: Plugin methods must be namespaced (`Discourse/Plugins/NamespaceMethods`)
- **Namespace constants**: Plugin constants must be namespaced (`Discourse/Plugins/NamespaceConstants`)
- **Use `require_relative`**: Not `require` for plugin-internal files (`Discourse/Plugins/UseRequireRelative`)
- **SyntaxTree formatting**: Ruby code is also checked by SyntaxTree for formatting consistency

#### Locale Files (i18n)
- **English locale lint**: `plugins/**/locales/{client,server}.en.yml` are validated by `script/i18n_lint.rb`
- Use proper YAML formatting, no duplicate keys, valid interpolation syntax

### Ruby
- **Guardian Extensions**: NEVER use `Guardian.class_eval`. Always use prepend mixin pattern:
```ruby
# ❌ WRONG - Monkey patching
Guardian.class_eval do
  def can_do_something?(obj)
    # logic
  end
end

# ✅ CORRECT - Prepend mixin
module GuardianExtensions
  def can_do_something?(obj)
    return false unless super  # Call original if overriding
    # additional logic
  end
end

Guardian.prepend GuardianExtensions
```

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
- **ALWAYS skip system tests** unless Playwright browsers are installed - use `--exclude-pattern "**/system/**"`

### RSpec Style
- **Context descriptions** MUST start with: `when`, `with`, `without`, `for`, `while`, `if`, `as`, `after`, or `in`
```ruby
# ❌ WRONG
context "uniqueness" do
context "cascade to lottery tickets" do

# ✅ CORRECT
context "with uniqueness validation" do
context "when cascading to lottery tickets" do
```

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

# IMPORTANT: Skip system tests if Playwright browsers not installed
# System tests require Playwright browsers which may not be available in all environments
# Always exclude system tests unless specifically testing UI functionality
LOAD_PLUGINS=1 bin/rspec plugins/vzekc-verlosung/spec --exclude-pattern "**/system/**"

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

**CRITICAL for Plugin Development:**

## Ruby/ESLint/Template Linting
- Linting commands MUST be run from the Discourse root directory (`/Users/hans/Development/vzekc/discourse`)
- Plugin file paths must be relative to Discourse root (e.g., `plugins/vzekc-verlosung/...`)
- DO NOT run linting from the plugin directory - there is no `bin/lint` there

## Prettier (JavaScript/CSS Formatting)
- **MUST be run from the plugin directory** (`/Users/hans/Development/vzekc/vzekc-verlosung`)
- Running prettier from Discourse root uses different config resolution and may pass incorrectly
- CI runs prettier from plugin directory context, so local checks must match
- The plugin has its own `node_modules` with prettier 3.6.2

```bash
# Ruby/ESLint/Template linting - From Discourse root directory
cd /Users/hans/Development/vzekc/discourse

# If Ruby linting fails with bundle errors, run bundle install first
bundle install

# Lint plugin files (use full relative paths)
bin/lint plugins/vzekc-verlosung/path/to/file plugins/vzekc-verlosung/path/to/another/file

# Auto-fix linting issues
bin/lint --fix plugins/vzekc-verlosung/path/to/file

# Lint recently changed files (works for core, may not detect plugin changes)
bin/lint --fix --recent

# If Ruby linting still fails after bundle install, use syntax check as fallback
ruby -c plugins/vzekc-verlosung/path/to/file.rb
```

```bash
# Prettier - From PLUGIN directory (CRITICAL!)
cd /Users/hans/Development/vzekc/vzekc-verlosung

# Check formatting (what CI runs)
pnpm prettier --check "assets/**/*.{scss,js,gjs,hbs}"

# Fix formatting issues
pnpm prettier --write "assets/**/*.{scss,js,gjs,hbs}"

# Check/fix specific file
pnpm prettier --check assets/javascripts/discourse/components/my-component.gjs
pnpm prettier --write assets/javascripts/discourse/components/my-component.gjs
```

**Example workflow for this plugin:**
```bash
# 1. Ruby/ESLint linting from Discourse root
cd /Users/hans/Development/vzekc/discourse
bin/lint --fix \
  plugins/vzekc-verlosung/plugin.rb \
  plugins/vzekc-verlosung/app/controllers/vzekc_verlosung/lotteries_controller.rb \
  plugins/vzekc-verlosung/assets/javascripts/discourse/components/my-component.gjs

# 2. Prettier formatting from plugin directory
cd /Users/hans/Development/vzekc/vzekc-verlosung
pnpm prettier --write "assets/**/*.{scss,js,gjs,hbs}"
```

**ALWAYS lint AND format your changes before committing!**

## Schema Annotations

**CRITICAL**: Schema annotations MUST be updated after adding database migrations.

### What Are Schema Annotations?

Schema annotations are auto-generated comments at the top of model files that document:
- Table columns and their types
- Indexes
- Foreign keys
- Constraints

Example:
```ruby
# == Schema Information
#
# Table name: vzekc_verlosung_donations
#
#  id                          :bigint           not null, primary key
#  erhaltungsbericht_topic_id  :bigint
#  ...
```

### When to Update Annotations

**ALWAYS update annotations after**:
- Adding/removing columns via migrations
- Adding/removing indexes
- Adding/removing foreign keys
- Any schema changes

### How to Update Annotations

**CRITICAL**: Annotations MUST be run from the Discourse root directory with LOAD_PLUGINS=1.

```bash
# From Discourse root directory
cd /Users/hans/Development/vzekc/discourse

# Update annotations for this plugin (preferred method)
LOAD_PLUGINS=1 bin/annotaterb models --model-dir plugins/vzekc-verlosung/app/models

# Alternative: Using rake task (requires temp database setup)
# LOAD_PLUGINS=1 bin/rake "annotate:clean:plugins[vzekc-verlosung]"
```

### CI Checks

CI runs `bin/rake annotate:ensure_all_indexes_are_unique` which verifies:
- Annotations match actual database schema
- All changes are properly documented

**If CI fails with annotation errors**:
1. Run the annotations rake task from Discourse root
2. Verify the schema comments in model files match your migrations
3. Commit the updated annotations

### Manual Annotation Updates

If the rake task fails (e.g., database connection issues), manually update the schema comment block:

1. Check your migration to see what columns/indexes/foreign keys were added
2. Update the `# == Schema Information` block in the model file
3. Follow the existing format exactly (column alignment, spacing)
4. Columns are listed alphabetically
5. Indexes are listed alphabetically by name
6. Foreign keys are listed with their constraints

### Common Pitfalls

- ❌ Forgetting to update annotations after migrations
- ❌ Running annotations from wrong directory (must be Discourse root)
- ❌ Missing LOAD_PLUGINS=1 flag
- ❌ Manually editing annotations without matching migration

## Site Settings
- Configured in `config/site_settings.yml` or `config/settings.yml` for plugins
- Functionality in `lib/site_setting_extension.rb`
- Access: `SiteSetting.setting_name` (Ruby), `siteSettings.setting_name` (JS with `@service siteSettings`)

### Type Coercion (CRITICAL)
**IMPORTANT**: Discourse SiteSettings have type-dependent behavior that causes bugs if not handled correctly.

#### Type Behavior
- **`type: integer`** → Automatically converted to Integer in Ruby ✅
  ```ruby
  # config/settings.yml: type: integer
  SiteSetting.reminder_hour.class  # => Integer
  Time.zone.now.hour == SiteSetting.reminder_hour  # ✅ Works correctly
  ```

- **`type: category`** → Stored as String in Ruby, must convert manually ⚠️
  ```ruby
  # config/settings.yml: type: category
  SiteSetting.my_category_id.class  # => String (e.g., "7")
  topic.category_id.class  # => Integer (e.g., 7)

  # ❌ WRONG - This will always fail!
  topic.category_id == SiteSetting.my_category_id  # false (7 != "7")

  # ✅ CORRECT - Convert to integer first
  topic.category_id == SiteSetting.my_category_id.to_i  # true
  ```

- **JavaScript** → All SiteSettings are strings, must parse manually ⚠️
  ```javascript
  // ❌ WRONG
  if (topic.category_id === this.siteSettings.my_category_id) { }

  // ✅ CORRECT
  const categoryId = parseInt(this.siteSettings.my_category_id, 10);
  if (topic.category_id === categoryId) { }
  ```

#### Common Pitfalls
1. **Tests passing but production failing**: Tests may inadvertently use integers while production has strings
   ```ruby
   # ❌ Test doesn't match production
   SiteSetting.my_category_id = category.id  # Integer in test

   # ✅ Test matches production
   SiteSetting.my_category_id = category.id.to_s  # String like production
   ```

2. **ActiveRecord queries handle conversion**: Using SiteSettings in `find_by` or `where` works fine
   ```ruby
   # ✅ These work even without .to_i (ActiveRecord converts)
   Category.find_by(id: SiteSetting.my_category_id)
   Category.where(id: SiteSetting.my_category_id)
   ```

#### Checklist for Category Settings
When working with category-type SiteSettings:
- [ ] Ruby comparisons: Use `.to_i` before comparing with integer values
- [ ] JavaScript comparisons: Use `parseInt(value, 10)` before comparing
- [ ] Tests: Set SiteSettings as strings (`.to_s`) to match production behavior
- [ ] ActiveRecord queries: No conversion needed (ActiveRecord handles it)

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

### Preloading Custom Fields (CRITICAL for Topic Lists)
**IMPORTANT**: When adding custom fields to `topic_list_item` serializer, you MUST follow this 3-step pattern to prevent N+1 queries:

```ruby
# Step 1: Register the custom field type
register_topic_custom_field_type("my_field", :boolean)

# Step 2: Preload for topic lists to prevent N+1 errors
add_preloaded_topic_list_custom_field("my_field")

# Step 3: Add helper method to Topic class (CRITICAL - don't skip this!)
add_to_class(:topic, :my_field) do
  custom_fields["my_field"] == true
end

# Step 4: Add to serializer - call the helper method, NOT custom_fields directly
add_to_serializer(:topic_list_item, :my_field) do
  object.my_field  # ← Calls the helper method, not custom_fields
end
```

**CRITICAL**: Never access `object.custom_fields["my_field"]` directly in the serializer. Always use a helper method. Even with preloading, direct access will trigger:
```
HasCustomFields::NotPreloadedError: Attempted to access the non preloaded custom field 'my_field' on the 'Topic' class.
```

**How it works**:
1. `add_preloaded_topic_list_custom_field` registers the field in `TopicList.preloaded_custom_fields`
2. When `TopicList#load_topics` runs, it calls `Topic.preload_custom_fields(@topics, preloaded_custom_fields)`
3. The helper method can safely access `custom_fields[key]` because the field is now preloaded
4. The serializer calls the helper method instead of accessing `custom_fields` directly

**Pattern Source**: See `/Users/hans/Development/vzekc/discourse/plugins/discourse-calendar/plugin.rb` lines 229-244 for a production example.

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

## Icons

**CRITICAL**: This section prevents recurring icon display issues. Read carefully before using icons.

### How Discourse Icons Work

Discourse uses an SVG sprite system for icons:
1. **Core Icons**: Discourse includes a curated subset of FontAwesome 6 icons in `/Users/hans/Development/vzekc/discourse/lib/svg_sprite.rb` (SVG_ICONS constant)
2. **Plugin Icons**: Plugins can register additional icons using `register_svg_icon` which adds them to `DiscoursePluginRegistry.svg_icons`
3. **Sprite Generation**: All registered icons are bundled into a single sprite at `/svg-sprite/[hostname]/svg-[theme_id]-[version].js`
4. **Icon Helper**: The `{{icon "name"}}` helper renders `<svg><use href="#name"/></svg>` which references the sprite

### Using Icons in Templates

**Syntax:**
```gjs
{{icon "icon-name"}}
{{icon "icon-name" class="custom-class"}}
{{icon "icon-name" title="Tooltip text"}}
```

**Examples:**
```gjs
{{icon "file-lines"}}  // File with lines icon
{{icon "check-circle"}}  // Check mark in circle
{{icon "far-file-lines"}}  // Regular (outlined) file with lines
```

### FontAwesome 6 Icon Names

**CRITICAL**: Use FontAwesome 6 names, NOT FontAwesome 5 names.

Common FA5 → FA6 renames:
- ❌ `file-alt` → ✅ `file-lines`
- ❌ `edit` → ✅ `pen-to-square`
- ❌ `trash` → ✅ `trash-can`
- ❌ `external-link-alt` → ✅ `arrow-up-right-from-square`

**Why this matters**: While Discourse includes some FA5 aliases for backward compatibility, they can be unreliable. Using modern FA6 names prevents display issues.

### Icon Availability

**Check if an icon is available:**
1. Look in `/Users/hans/Development/vzekc/discourse/lib/svg_sprite.rb` (SVG_ICONS constant)
2. Check FontAwesome 6 free icon library: https://fontawesome.com/search?o=r&m=free
3. Verify in Rails console: `SvgSprite.bundle.include?("icon-name")`

**Common available icons** (no registration needed):
- `file`, `file-lines` (solid file with lines)
- `check`, `check-circle`
- `times`, `times-circle`
- `users`, `user`, `user-plus`
- `calendar`, `calendar-plus`, `calendar-check`
- `box`, `gift`, `trophy`
- `dice`, `clock`, `pen`

**Icon Prefixes:**
- No prefix = Solid style (default)
- `far-` = Regular style (outlined)
- `fab-` = Brands (company logos)

### When to Register Icons

**DO NOT register** if the icon is already in Discourse core (check `lib/svg_sprite.rb` first).

**DO register** if:
- Icon is in FontAwesome 6 free but NOT in Discourse core
- Using a custom SVG icon

**How to register:**
```ruby
# In plugin.rb
register_svg_icon "trophy"  # Only if not in core
```

### Custom SVG Icons

If you need truly custom icons not in FontAwesome:

1. **Create sprite file**: `plugins/vzekc-verlosung/svg-icons/custom.svg`
2. **Format as SVG sprite**:
```xml
<svg xmlns="http://www.w3.org/2000/svg" style="display: none;">
  <symbol id="my-custom-icon" viewBox="0 0 512 512">
    <path d="M..."/>
  </symbol>
</svg>
```
3. **Register in plugin.rb**:
```ruby
register_svg_icon "my-custom-icon"
```

### Common Pitfalls

❌ **Using old FontAwesome 5 names**
```gjs
{{icon "file-alt"}}  // May not render
```
✅ **Use FontAwesome 6 names**
```gjs
{{icon "file-lines"}}  // Renders correctly
```

❌ **Registering icons already in core**
```ruby
register_svg_icon "file-lines"  // Unnecessary, already in core
```
✅ **Only register what's needed**
```ruby
# Check lib/svg_sprite.rb first
register_svg_icon "trophy"  // Only if not in core
```

❌ **Forgetting icon prefix for regular/brands**
```gjs
{{icon "github"}}  // Won't work
```
✅ **Use correct prefix**
```gjs
{{icon "fab-github"}}  // Brands need fab- prefix
```

### Troubleshooting

**Icon not showing?**
1. Check if using FA6 name (not FA5)
2. Verify icon exists in `/Users/hans/Development/vzekc/discourse/lib/svg_sprite.rb`
3. Check if registration needed (and added to plugin.rb)
4. Verify correct prefix (far-, fab-)
5. Restart server after adding registrations
6. Clear browser cache

**After adding new icons:**
- Restart Discourse server
- Clear browser cache
- Check browser console for SVG sprite errors

## Knowledge Sharing
- ALWAYS persist information for ALL developers (no conversational-only memory)
- Follow project conventions, prevent knowledge silos
- Recommend storage locations by info type
- Inform when this file changes and reloads
- overall, we want the business logic schema to be separate from posts.  posts can link back to business objects if that is useful when displaying or creating ui
elements, but the business state should be completely represented in separate tables.  note that deleting posts possibly needs to update the business state, and we need
 to have proper hooks for that