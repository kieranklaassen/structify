---
status: pending
priority: p3
issue_id: "005"
tags: [code-review, documentation]
dependencies: []
---

# Add Migration Guide for Breaking Changes

## Problem Statement

The PR introduces breaking changes without a migration guide for users upgrading from 0.x to 1.0.

## Findings

**Breaking changes:**
1. DSL syntax changed: `field :title, :string` → `string :title`
2. Fields required by default (was optional by default)
3. Versioning features removed (`version`, `versions:` parameter)
4. `SchemaSerializer` removed

**Source:** Kieran Rails Reviewer, DHH Rails Reviewer

## Proposed Solutions

### Option 1: Add Upgrade Section to README (Recommended)
**Pros:** Easy to find, standard practice
**Cons:** Makes README longer
**Effort:** Small (30 min)
**Risk:** None

### Option 2: Separate UPGRADING.md
**Pros:** Detailed, won't clutter README
**Cons:** May be missed by users
**Effort:** Small
**Risk:** None

## Recommended Action

Option 1 - Add to README

## Technical Details

**Affected files:**
- `/README.md`

**Content to add:**
```markdown
## Upgrading from 0.x to 1.0

### Breaking Changes

1. **Schema DSL syntax changed**:
   ```ruby
   # OLD (0.x)
   schema_definition do
     field :title, :string, required: true
     field :count, :integer
   end

   # NEW (1.0)
   schema_definition do
     string :title
     integer :count, required: false  # Note: required by default in 1.0
   end
   ```

2. **Required by default**: In 1.0, all fields are required unless you specify `required: false`

3. **Versioning removed**: If you used `version`, `stored_version`, or `version_compatible_with?`, these features are no longer available.
```

## Acceptance Criteria

- [ ] Add "Upgrading from 0.x to 1.0" section to README
- [ ] Document all breaking changes
- [ ] Provide before/after code examples
- [ ] Note what features were removed

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-02 | Created from code review | Migration guides prevent user frustration |

## Resources

- PR #5: https://github.com/kieranklaassen/structify/pull/5
