---
status: pending
priority: p3
issue_id: "006"
tags: [code-review, security, documentation]
dependencies: []
---

# Document Error Message Data Leakage Risk

## Problem Statement

Error messages include field values that may contain sensitive LLM-extracted data (PII, credentials, financial data). This could leak into logs, monitoring, or error tracking services.

## Findings

**Error message format:**
```ruby
# lib/structify.rb:72
message = "Field '#{field_name}' expected #{expected_type}, got #{actual_type}: #{value.inspect}"
```

**Potential leak scenario:**
```ruby
# If LLM extracts SSN
article.ssn = "invalid-type"
article.save!
# Exception message: "Field 'ssn' expected string, got integer: 123456789"
# This could be logged, sent to Sentry, etc.
```

**Source:** Security Sentinel Agent

## Proposed Solutions

### Option 1: Documentation Warning (Recommended for now)
**Pros:** Quick, low risk
**Cons:** Doesn't prevent leakage
**Effort:** Trivial (10 min)
**Risk:** None

Add to README:
```markdown
### Security Note

Validation error messages include field values for debugging.
If you extract sensitive data (PII, credentials), ensure your
error handling sanitizes exceptions before logging.
```

### Option 2: Add safe_message Method (Future)
**Pros:** Prevents leakage at source
**Cons:** More work
**Effort:** Medium
**Risk:** Low

```ruby
def safe_message
  message.gsub(@value.to_s, '[REDACTED]')
end
```

## Recommended Action

Option 1 for now - document the risk. Consider Option 2 for future release.

## Technical Details

**Affected files:**
- `/README.md` - Add security note

## Acceptance Criteria

- [ ] Add security note to README about error message content
- [ ] Recommend error handling approach
- [ ] Consider adding `safe_message` in future release

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-02 | Created from code review | LLM data may be sensitive |

## Resources

- PR #5: https://github.com/kieranklaassen/structify/pull/5
- Security Sentinel analysis
