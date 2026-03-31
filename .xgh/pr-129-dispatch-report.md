# PR #129 Dispatch Report — Cycle 1A

**Status**: ACTED
**Timestamp**: 2026-03-25T22:00:00Z
**PR**: 129 (extreme-go-horse/xgh)

---

## Summary

Copilot reviewed the PR with 11 actionable comments. Dispatched **Cycle 1A** agents to address critical shell guards and formatting issues affecting error handling, sourcing safety, and token budget.

### Comments Baseline
- **Previous**: 0 comments
- **Current**: 15 inline comments from Copilot
- **New since last baseline**: 15 comments
- **Last review**: 2026-03-25T21:30:10Z

---

## Cycle 1A — Dispatch Details

**Agent**: sonnet-fix-pr129-guards-formatting
**Started**: 2026-03-25T22:00:00Z
**Status**: ACTIVE

### Fixes Deployed

| File | Issue | Fix | Comment ID |
|------|-------|-----|------------|
| `lib/preferences.sh` | Unconditional `set -euo pipefail` breaks caller shell options | Wrap in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` conditional | 2991120393 |
| `hooks/_pref-index-builder.sh` | Leading spaces in `PREF_INDEX_CONTEXT` waste token budget | Remove leading spaces, start multiline string at column 1 | 2991120433 |
| `hooks/_pref-index-builder.sh` | `find` command fails when `.xgh/` missing; exits with `set -e` | Guard with directory check: `if [[ -d "$project_root/.xgh" ]]` | 2991153980 |
| `hooks/session-start-preferences.sh` | Unguarded `source` helper; exits non-zero if file missing | Add file existence check before sourcing | 2991153881 |
| `hooks/post-compact-preferences.sh` | Unguarded `source` helper; exits non-zero if file missing | Add file existence check before sourcing | 2991153899 |

**Commit Message**:
```
fix: add shell guards + format preference context injection

Address Copilot review (PR #129):
- Add conditional set -euo pipefail guard to lib/preferences.sh (sourced by config-reader)
- Remove leading spaces from PREF_INDEX_CONTEXT to avoid token waste
- Guard find command with directory existence check
- Add file existence checks before sourcing helper in both hooks

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## Remaining Comments (for Cycle 1B/1C)

### Group 2: Schema/Reference Inconsistencies (7 comments)
Files: `skills/_shared/references/project-preferences.md`
- Domain field definitions mismatch actual `config/project.yaml` schema (5 domains: vcs, testing, scheduling, notifications, retrieval)
- Example uses wrong field names + empty branch argument
- "Built-in defaults" text refers to non-existent layer
- Import statement says "stdlib only" but uses PyYAML

**Planned**: Cycle 1B — Deploy sonnet-fix-pr129-schema-refs

### Group 3: Validation/Error Handling Logic (3 comments)
Files: `tests/test-hook-ordering.sh`, `skills/validate-project-prefs/validate-project-prefs.md`
- Missing guard for empty `first_bash_index` before jq --argjson usage
- Domain coverage check uses fragile grep regex; should use yq for YAML parsing

**Planned**: Cycle 1B — Deploy sonnet-fix-pr129-validation (dependent on Cycle 1A guards being fixed)

---

## State File Updates

- **baseline_comment_count**: 0 → 15
- **baseline_review_at**: 2026-03-25T21:17:25Z → 2026-03-25T21:30:10Z
- **last_action**: review_pending → dispatched_sonnet_cycle1a_guards_formatting
- **active_agent**: null → sonnet-fix-pr129-guards-formatting
- **active_agent_started_at**: null → 2026-03-25T22:00:00Z
- **fix_cycles**: 0 → 1

---

## Next Steps

1. **Monitor**: Wait for sonnet-fix-pr129-guards-formatting to complete and push
2. **Re-review**: Copilot auto-reviews on push (check review_on_push setting)
3. **Cycle 1B**: After Cycle 1A merges, dispatch schema/reference fixes (7 comments)
4. **Cycle 1C**: After Cycle 1B, deploy validation logic fixes (3 comments)
5. **Merge**: After all cycles complete and re-review passes, merge with --squash

---

## Configuration

- **Merge method**: squash
- **Accept suggestion commits**: true
- **Require resolved threads**: true
- **Max fix cycles**: 3
- **Poll interval**: 3m
