---
status: pending
priority: p3
issue_id: "004"
tags: [code-review, cleanup, dry]
dependencies: ["003"]
---

# Simplify Hash Access Pattern

## Problem Statement

The pattern `hash[:key] || hash["key"]` is repeated 15+ times throughout the codebase, suggesting uncertainty about the ruby_llm-schema contract.

## Findings

**Pattern repeated:**
```ruby
schema_object = raw_schema[:schema] || raw_schema["schema"] || {}
properties = schema_object[:properties] || schema_object["properties"] || {}
required_fields = schema_object[:required] || schema_object["required"] || []
```

**Locations:**
- `model.rb` (lines 77, 79, 84-87, 107-108)
- `field_validation.rb` (lines 42-46, 63, 68-69, and many more)

**Source:** Pattern Recognition Agent, Code Simplicity Agent

## Proposed Solutions

### Option 1: Verify ruby_llm-schema Output and Trust It (Recommended)
**Pros:** Cleaner code, trust the contract
**Cons:** Need to verify output format first
**Effort:** Small (20 min)
**Risk:** Low

First verify what ruby_llm-schema returns, then use consistently:
```ruby
# If it returns symbols (likely):
properties = schema_object[:properties] || {}
```

### Option 2: Normalize Once at Boundary
**Pros:** Defensive, handles any format
**Cons:** Extra processing
**Effort:** Small
**Risk:** Very Low

```ruby
def normalized_schema
  @normalized_schema ||= deep_symbolize_keys(structify_schema.new.to_json_schema)
end
```

## Recommended Action

Option 1 - Verify the contract and trust it (combine with caching todo)

## Technical Details

**Affected files:**
- `/lib/structify/model.rb`
- `/lib/structify/field_validation.rb`

**Instances to update:** ~15+

## Acceptance Criteria

- [ ] Verify ruby_llm-schema hash key format
- [ ] Remove redundant `|| hash["string_key"]` checks
- [ ] All tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-02 | Created from code review | Verify contract before trusting |

## Resources

- PR #5: https://github.com/kieranklaassen/structify/pull/5
