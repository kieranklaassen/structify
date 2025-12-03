---
status: pending
priority: p2
issue_id: "002"
tags: [code-review, bug-prevention, rails]
dependencies: []
---

# Fix rescue nil Anti-Pattern

## Problem Statement

Bare `rescue nil` silently swallows ALL exceptions, making debugging difficult and potentially hiding real bugs.

## Findings

**Location:** `/lib/structify/field_validation.rb:55`

```ruby
def validate_field(field_name, field_def, is_required)
  value = send(field_name) rescue nil  # PROBLEMATIC
  # ...
end
```

**What this catches:**
- `NoMethodError` (intended)
- `SystemStackError` (infinite recursion - should NOT be caught)
- Any `StandardError` subclass (should NOT be caught)

**Potential issue:** If a getter raises an exception for a legitimate reason (e.g., database connection error, stack overflow), it gets silently converted to `nil`, then raises a misleading `RequiredFieldError`.

**Source:** Kieran Rails Reviewer, Security Sentinel, Pattern Recognition Agent

## Proposed Solutions

### Option 1: Use respond_to? Check (Recommended)
**Pros:** Explicit, safe, no exception handling needed
**Cons:** None
**Effort:** Trivial (5 min)
**Risk:** None

```ruby
value = respond_to?(field_name) ? send(field_name) : nil
```

### Option 2: Rescue Specific Exception
**Pros:** Clear about what we're catching
**Cons:** Slightly more verbose
**Effort:** Trivial (5 min)
**Risk:** None

```ruby
value = begin
  send(field_name)
rescue NoMethodError
  nil
end
```

## Recommended Action

Option 1 - Use `respond_to?` check (cleaner and more explicit)

## Technical Details

**Affected files:**
- `/lib/structify/field_validation.rb` (line 55)

## Acceptance Criteria

- [ ] Replace `rescue nil` with explicit check
- [ ] All existing tests pass
- [ ] Add test for missing field accessor scenario

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-02 | Created from code review | Silent exception swallowing is dangerous |

## Resources

- PR #5: https://github.com/kieranklaassen/structify/pull/5
