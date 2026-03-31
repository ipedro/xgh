# PR #129 Fix Dispatch Plan — Phase 1

## PR Overview
- **Title**: feat: expand validate-project-prefs + Phase 1 plan
- **Mergeable**: MERGEABLE
- **CI Status**: No checks yet
- **Review State**: COMMENTED (11 new comments since baseline)
- **Baseline**: 0 comments; last_review_at: 2026-03-25T21:17:25Z

## New Comments Summary (11 total)

### Fix Group 1: Shell Options + Guard Conditions (Logic/Correctness)
**Agent**: sonnet (complex, error-handling critical)

1. **lib/preferences.sh** (comment 2991120393)
   - Issue: Unconditionally runs `set -euo pipefail` when sourced, breaks caller shell options
   - Fix: Add conditional `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` guard
   - Suggestion provided

2. **hooks/_pref-index-builder.sh** (comment 2991153881, 2991153899)
   - Dual issue: Two hooks (`session-start-preferences.sh`, `post-compact-preferences.sh`) source helper unguarded
   - Fix: Check file existence before sourcing or graceful fallback
   - Suggestion provided for guard pattern

3. **hooks/_pref-index-builder.sh** (comment 2991153980)
   - Issue: `find | wc -l` fails when `.xgh/` doesn't exist; exits with `set -e`
   - Fix: Guard with directory check, treat missing as count=0
   - Suggestion provided

### Fix Group 2: Indentation/Formatting (Style)
**Agent**: haiku (simple, no logic impact)

4. **hooks/_pref-index-builder.sh** (comment 2991120433)
   - Issue: `PREF_INDEX_CONTEXT` has leading spaces, indents all injected lines (wastes token budget)
   - Fix: Remove leading spaces from multi-line string
   - Suggestion provided

### Fix Group 3: Reference/Schema Documentation (Consistency)
**Agent**: sonnet (complex, schema-aware, multiple files)

5. **skills/_shared/references/project-preferences.md** (comments 2991120455, 2991120472, 2991153809, 2991153830, 2991153854, 2991153973)
   - Issues: Domain field details list mismatches actual `config/project.yaml` schema (5 separate table updates)
   - Issues: Example uses wrong field names and empty branch (conflicts w/ loader contract)
   - Issues: "Built-in defaults" text mentions non-existent layer; PyYAML import but says "stdlib only"
   - Fixes: Update all 5 domain detail tables; fix example; update wording
   - Suggestions provided for each domain

### Fix Group 4: Validation Logic (Error Handling)
**Agent**: sonnet (complex, jq + error handling)

6. **tests/test-hook-ordering.sh** (comment 2991153776)
   - Issue: `first_bash_index` empty check missing; causes `jq --argjson` to error
   - Fix: Add guard before using as `--argjson`, fail gracefully with message
   - Suggestion provided

7. **skills/validate-project-prefs/validate-project-prefs.md** (comment 2991120478)
   - Issue: Domain coverage check uses indentation-sensitive `grep` regex; can false-fail
   - Fix: Use `yq` instead for robust YAML key presence check
   - Suggestion provided

## Dispatch Strategy

### Cycle 1 (this dispatch)
- **Cycle 1A (parallel)**:
  - Deploy **sonnet-fix-pr129-guards** to fix all guard conditions (Group 1: comments 1, 2, 3)
  - Deploy **haiku-fix-pr129-indentation** to fix formatting (Group 2: comment 4)

- **Cycle 1B (after 1A merges)**:
  - Deploy **sonnet-fix-pr129-schema-refs** to fix domain field documentation (Group 3: comment 5)
  - Deploy **sonnet-fix-pr129-validation** to fix validation logic (Group 4: comment 6, 7)

Rationale:
- Group 1 is critical (shell safety); Group 2 is safe/independent
- Group 3 depends on correct logic from Group 1
- Group 4 depends on Group 1 being fixed (can't test ordering if guards fail)
- Max 3 cycles, so we batch fixes where dependencies allow

## Files to Fix (in order)

**Cycle 1A:**
1. `lib/preferences.sh` — add conditional `set` guard
2. `hooks/_pref-index-builder.sh` — add file existence check + dir existence check
3. `hooks/session-start-preferences.sh` — add file existence guard
4. `hooks/post-compact-preferences.sh` — add file existence guard
5. `hooks/_pref-index-builder.sh` — remove leading spaces from `PREF_INDEX_CONTEXT`

**Cycle 1B:**
1. `skills/_shared/references/project-preferences.md` — update all 5 domain tables + example + text
2. `tests/test-hook-ordering.sh` — add empty `first_bash_index` guard
3. `skills/validate-project-prefs/validate-project-prefs.md` — replace grep with yq

## Notes
- No `require_resolved_threads: true` thread actions needed (all inline comment threads)
- All changes are file edits; no new files
- Copilot will auto-re-review on push (check `review_on_push` setting)
- Total estimated fixes: 7 files, ~20 lines changed

---
*Dispatch initiated: 2026-03-25T22:00:00Z*
