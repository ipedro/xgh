# PR #131 Copilot Review — Fix Plan

**Status:** Poll cycle 5 — Copilot reviewed with 6 comments (COMMENTED, not APPROVED)
**Branch:** docs/phase-2-validate-observe-spec
**File:** `.xgh/specs/2026-03-26-phase-2-validate-observe-design.md`

## Comments Summary

All 6 comments are inline review comments on the design spec file. No code changes required — all are documentation clarity and correctness fixes.

### Comment 1: Snapshot seeding snippet (line 216)
**Issue:** `$HOOK_INPUT` and `$TMPDIR` references unsafe; spec doesn't show how to handle unset vars with `set -euo pipefail`.

**Fix:** Replace the snippet with a safer version that:
- Reads stdin into `HOOK_INPUT` if not already set
- Uses safe temp dir: `${TMPDIR:-/tmp}` instead of bare `$TMPDIR`
- Includes the shellcheck-friendly guard: `: \"${HOOK_INPUT:=}\"`

**Suggestion provided:** Yes, use as-is

---

### Comment 2: lib/severity.sh sample (line 200)
**Issue:** Omits repo convention (strict mode only when executed, not sourced) and doesn't document `lib/preferences.sh` dependency.

**Fix:** Update snippet to match existing `lib/` patterns:
- Add guard for `set -euo pipefail` (only if script is executed, not sourced)
- Document that `lib/preferences.sh` must be sourced first
- Mention `_pref_read_yaml` dependency in prose

**Action:** Update spec prose and snippet to match `lib/preferences.sh` conventions

---

### Comment 3: Table formatting (line 19) — Design Decisions table
**Issue:** Leading `||` creates an empty first column in GitHub Markdown.

**Fix:** Replace `|| ...` with `| ...` at the start of each row; adjust separator row from `|---|` to align with single-pipe format.

---

### Comment 4: Table formatting (line 40) — New Checks table
**Issue:** Same issue — leading `||` creates empty column.

**Fix:** Switch to single-pipe `|` format for consistency with other repo specs.

---

### Comment 5: PreToolUse warning output format (line 67)
**Issue:** Spec says `{ "systemMessage": "..." }` but Phase 1 spec and existing hooks use `additionalContext` for warnings.

**Fix:** Replace suggestion text to match Phase 1 design:
```
5. `warn` → `{"hookSpecificOutput": {"additionalContext": "..."}}`
```

**Suggestion provided:** Yes, use as-is

---

### Comment 6: Protected branches schema (line 94)
**Issue:** Spec references "existing `preferences.vcs.branches.<name>` schema" but `config/project.yaml` has no such schema. Either clarify that Phase 2 introduces it, or reconcile with existing `preferences.pr.branches`.

**Fix:** Use provided suggestion to clarify Phase 2 introduces new schema:
```
Phase 2 introduces a new `preferences.vcs.branches.<name>` map with a `protected: true` field for protected branches; existing `preferences.pr.branches`-based hooks will be migrated to this schema — no separate flat list is added.
```

**Suggestion provided:** Yes, use as-is

---

## Fix Strategy

- **Type:** Documentation-only spec corrections
- **Scope:** Single file `.xgh/specs/2026-03-26-phase-2-validate-observe-design.md`
- **Approach:**
  1. Fix 3 Markdown table formatting issues (comments 3, 4)
  2. Accept 3 suggestion commits (comments 1, 5, 6)
  3. Manually update comment 2 prose to document sourcing conventions
  4. Verify all changes are in-scope (doc only, no logic changes)
  5. Commit with message referencing all 6 comments

## Merge Criteria Post-Fix

After fixes pushed:
- Re-request Copilot review (reviewer list cycle)
- If approved (state == "APPROVED"), merge with squash
- If COMMENTED again, repeat fix cycle (max 3 total)
