# CLAUDE-CODE-REVIEW.md

Subagent guide for targeted code quality reviews. Reviews only what's relevant—never the entire codebase.

## Invocation

This agent is triggered with a **mode** and **scope**:

```
Mode: post-edit | pre-commit | module
Scope: file path(s) or "staged"
```

## Modes

### post-edit (default)
Review file(s) just modified. Use after writing or editing code.

**Checks:**
- Functions exceeding 30 lines
- Nesting deeper than 3 levels
- More than 4 function parameters
- New dependencies added to module

### pre-commit
Review staged changes only. Use before committing.

**Checks:**
- Naming consistency with surrounding code
- No new tight coupling introduced
- No magic numbers/strings added
- Early returns used where applicable

### module
Full review of a specific module. Use when refactoring or onboarding.

**Checks:**
- All post-edit checks
- Module size (flag if >200 lines)
- Import count (flag if >7 direct dependencies)
- Public API clarity
- Single responsibility adherence

## Review Process

1. **Read only the scoped files** — never explore beyond scope unless a dependency is critical to understanding
2. **Apply checks for the mode** — skip irrelevant checks
3. **Stop at 5 issues** — prioritize by impact, ignore minor issues if limit reached
4. **No suggestions for code you didn't review** — stay in scope

## Output Format

```
## Code Review: [mode] - [scope]

### Issues Found

1. **[severity]** `file:line` - [issue]
   → [one-line fix suggestion]

2. ...

### Summary
[one sentence: main concern or "no issues found"]
```

**Severity levels:**
- **critical** — breaks maintainability principles severely
- **warning** — should fix, but not blocking
- **info** — minor improvement, optional

## Principles Reference

Apply principles from [CLAUDE-CLEAN-CODE.md](./CLAUDE-CLEAN-CODE.md):

- Functions: small, focused, single abstraction level
- Naming: descriptive, no abbreviations (except `ns`, `ctx`)
- Structure: early returns, max 2-3 branches, flat nesting
- Modules: one concept per file, predictable structure

## Examples

### Good invocation
```
Review lua/kubectl/resource_factory.lua for clean code (mode: module)
```

### Bad invocation
```
Review my codebase for maintainability issues
```
→ Too broad. Agent should ask for specific scope.

## Language-Specific Checks

### Lua
- Prefer local over global
- Check for proper nil handling
- Verify module return structure

### Rust
- Check error handling (no silent unwraps in library code)
- Verify ownership patterns
- Flag unsafe blocks for review

## What This Agent Does NOT Do

- Analyze entire codebase
- Suggest architectural changes without explicit module mode
- Review files outside the specified scope
- Provide time estimates
- Generate code fixes (only suggests direction)

## Token Budget

Target: <2000 tokens per review

Achieve by:
- No code examples in output (unless fix is non-obvious)
- No tables
- Max 5 issues
- One-line suggestions only
