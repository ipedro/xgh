# PR #132 Review Comments — Phase 2 Validate + Observe

**Baseline:** 8 comments
**New comments:** 10 (total 18)
**Last review:** 2026-03-26T01:24:49Z

---

## Comments Summary (in order of appearance)

### 1. Force-push check — brittle branch parsing
**File:** `hooks/pre-tool-use-preferences.sh`
**Issue:** Branch parsing via `sed 's/-f//g'` can corrupt args with "-f" in branch names; extracting target as 2nd positional arg breaks for `HEAD:main` refspec syntax.
**Fix:** Tokenize args as bash array, handle `remote:refspec` patterns explicitly.

### 2. Protected-branch lookups — yq path parsing issue
**File:** `hooks/pre-tool-use-preferences.sh`
**Issue:** dotted path lookup won't work for branches with `/` or `.` in names; inconsistent with existing `_pref_read_branch` helper.
**Fix:** Use `_pref_read_branch "vcs" "$PUSH_BRANCH" "protected"` instead.

### 3. Bash 4+ associative array — macOS Bash 3.2 compat
**File:** `lib/severity.sh`
**Issue:** `declare -A` requires Bash 4+; macOS system Bash is 3.2. Repo docs emphasize no extra runtime.
**Fix:** Replace with POSIX fallback (case statement) or add version guard + documented dependency.

### 4. JSON escaping in test helper
**File:** `tests/test-pre-tool-use-validation.sh`
**Issue:** `make_input` interpolates command directly into JSON without escaping; quotes/backslashes break JSON validity.
**Suggestion:**
```bash
jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
```

### 5. Invalid JSON validation logic
**File:** `tests/test-pre-tool-use-validation.sh`
**Issue:** "merge method match" assertion passes even if hook outputs invalid JSON (jq parse failure falls through to pass case).
**Suggestion:** Explicitly fail when `jq` can't parse non-empty output.

### 6. Wrong schema key in diagnosis message
**File:** `hooks/post-tool-use-failure-preferences.sh`
**Issue:** References `preferences.pr.reviewers` but schema uses `preferences.pr.reviewer` (singular).
**Suggestion:**
```bash
_emit_diagnosis "[xgh] Reviewer not found — verify preferences.pr.reviewer and bot installation.${HINT}"
```

### 7. Drift leaf diff flattening — depth logic off-by-one
**File:** `hooks/post-tool-use-preferences.sh`
**Issue:** With `max_depth=5` and `depth < max_depth - 1` condition, leaves like `preferences.vcs.checks.branch_naming.severity` are recorded at parent level, hiding which exact field changed.
**Fix:** Flatten dicts all the way to scalars (or adjust depth so level-5 leaves are included).

### 8. TTY stdin blocking in session-start hook
**File:** `hooks/session-start-preferences.sh` (line 70)
**Issue:** `HOOK_INPUT=$(cat …)` blocks indefinitely when stdin is inherited TTY (terminal or direct script invocation).
**Fix:** Guard read with `-t 0` check or use timed read; treat missing stdin as "no session_id".

### 9. Commit message extraction — unquoted messages not validated
**File:** `hooks/pre-tool-use-preferences.sh` (line 183)
**Issue:** Only matches quoted values for `-m` / `--message`; `git commit -m feat:foo` skips validation entirely.
**Fix:** Support unquoted messages (single-token) in addition to quoted ones.

### 10. Unused `tool` parameter in test helper
**File:** `tests/test-pre-tool-use-validation.sh` (line 20)
**Issue:** `make_input()` takes `tool` parameter but always emits `tool_name: "Bash"`.
**Suggestion:**
```bash
jq -n --arg tool "$tool" --arg cmd "$cmd" '{"tool_name":$tool,"tool_input":{"command":$cmd}}'
```

---

## Bonus observation (comment 11 — merge-method validation fail-open)
**File:** `hooks/pre-tool-use-preferences.sh` (line 83)
**Issue:** Can incorrectly deny when target branch can't be determined; blocking check should fail-open.
**Fix:** Return 0 (silent pass) if `TARGET_BRANCH` is empty.

---

## Fix strategy
- **Bash 4+ compat (comment 3):** Decide on strategy — new version guard or POSIX fallback?
- **JSON escaping (comments 4–5, 10):** Use `jq -n --arg` in all test helpers.
- **Branch parsing (comments 1–2):** Refactor arg tokenization + use `_pref_read_branch`.
- **Schema/config fixes (comment 6, 9, 11):** Straightforward corrections.
- **Drift flattening (comment 7):** Clarify depth logic in Python snippet.
- **TTY blocking (comment 8):** Add stdin guard.

**Constraint:** Fix only what Copilot flagged — no scope creep. Commit and push when done.
