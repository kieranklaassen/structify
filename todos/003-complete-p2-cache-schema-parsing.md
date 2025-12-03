---
status: pending
priority: p2
issue_id: "003"
tags: [code-review, performance, optimization]
dependencies: []
---

# Cache Schema Parsing at Class Level

## Problem Statement

Schema is re-parsed from `ruby_llm-schema` on every validation, creating unnecessary overhead and GC pressure at scale.

## Findings

**Current behavior:**
```ruby
# Called on every validation (field_validation.rb:40)
schema_hash = self.class.structify_schema.new.to_json_schema

# Also in json_schema method (model.rb:76)
raw_schema = structify_schema.new.to_json_schema
```

**Performance impact:**
- Each call creates new schema instance (~40 bytes)
- Each call generates new hash (~200+ bytes)
- At 1000 validations: ~800KB-1MB allocated
- Validation overhead: ~30% attributable to schema parsing

**Source:** Performance Oracle Agent, Architecture Strategist

## Proposed Solutions

### Option 1: Class-Level Memoization (Recommended)
**Pros:** Simple, thread-safe, significant improvement
**Cons:** Minor memory increase (1KB per model class)
**Effort:** Small (30 min)
**Risk:** Very Low

```ruby
# In model.rb ClassMethods
def cached_json_schema
  @cached_json_schema ||= structify_schema.new.to_json_schema
end

def cached_properties
  @cached_properties ||= begin
    schema = cached_json_schema
    schema_object = schema[:schema] || schema
    schema_object[:properties] || {}
  end
end

def cached_required_fields
  @cached_required_fields ||= begin
    schema = cached_json_schema
    schema_object = schema[:schema] || schema
    (schema_object[:required] || []).map(&:to_s)
  end
end
```

Then in field_validation.rb:
```ruby
def validate_structify_fields
  return unless self.class.structify_schema
  properties = self.class.cached_properties
  required_strings = self.class.cached_required_fields
  # ...
end
```

### Option 2: Instance-Level Memoization
**Pros:** Per-instance cache
**Cons:** Wastes memory on repeated instantiation
**Effort:** Small
**Risk:** Low

## Recommended Action

Option 1 - Class-level memoization (schema is immutable after class definition)

## Technical Details

**Affected files:**
- `/lib/structify/model.rb` - Add caching methods
- `/lib/structify/field_validation.rb` - Use cached data

**Expected improvement:**
- 30-40% faster validation
- 40% less GC pressure
- Thread-safe (using `||=` with immutable data)

## Acceptance Criteria

- [ ] Add `cached_json_schema` class method
- [ ] Add `cached_properties` class method
- [ ] Add `cached_required_fields` class method
- [ ] Update `validate_structify_fields` to use cached data
- [ ] Update `json_schema` to use cached data
- [ ] All existing tests pass
- [ ] Add benchmark test (optional)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-02 | Created from code review | Schema is immutable - safe to cache |

## Resources

- PR #5: https://github.com/kieranklaassen/structify/pull/5
- Performance Oracle analysis
