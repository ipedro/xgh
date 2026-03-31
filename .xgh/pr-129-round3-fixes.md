# PR 129 — Round 3 Fixes (3/3)

**Copilot has posted 5 new comments on fixes from Round 2. Address all of them. This is the final fix cycle before merge.**

## New Comments to Address

### 1. hooks/session-start-preferences.sh (line 55) — _yaml_is_valid validator handling
**Issue:** _yaml_is_valid returns failure when neither yq nor python3+PyYAML are available, emitting a false "syntax error" warning. Should distinguish "no validator available" (return 2) from actual YAML errors (return 1).

**Current:**
```bash
# Current code attempts validation but doesn't distinguish "not available" from "invalid"
```

**Fix:** Refactor _yaml_is_valid to:
- Return 0 if valid
- Return 1 if syntax error detected
- Return 2 if no validator available (yq and python3+PyYAML both missing)
- Update the caller to only emit "syntax error" warning when status==1, not when status==2

**Files:** `/Users/pedro/Developer/xgh/hooks/session-start-preferences.sh`

---

### 2. hooks/post-compact-preferences.sh (line 61) — Same validator + caller fix
**Issue:** Caller treats "no validator available" (return 2) as a syntax error. Should handle all three cases: valid (0), invalid (1), unavailable (2).

**Fix:** Apply the same _yaml_is_valid refactor + update the caller logic:
- Status 0 (valid) or 2 (unavailable) → proceed to preference index build
- Status 1 (invalid) → emit warning and exit
- Remove the false negative for minimal environments

**Files:** `/Users/pedro/Developer/xgh/hooks/post-compact-preferences.sh`

---

### 3. hooks/_pref-index-builder.sh (line 16) — Shebang + strict mode
**Issue:** Has shebang but doesn't set strict mode. When sourced, doesn't guard it. Should add guarded `set -euo pipefail`.

**Fix:** Add at line 16:
```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi
```

**Files:** `/Users/pedro/Developer/xgh/hooks/_pref-index-builder.sh`

---

### 4. lib/preferences.sh (line 82) — _pref_read_branch escaping for branch names
**Issue:** Builds dotted yq path using raw branch name. Branch names with `-`, `/`, `.` are interpreted as yq operators, causing silent failures for refs like `release-1.0` or `feature/foo`.

**Fix:** Use bracket-quoted key access `branches["$branch"]` instead of dotted notation so branch names are treated as literal keys:
```bash
yq_path=".preferences.${domain}.branches[\"${branch}\"].${field}"
```

**Files:** `/Users/pedro/Developer/xgh/lib/preferences.sh` — in the `_pref_read_branch()` function

---

### 5. lib/preferences.sh (line 67) — _pref_read_yaml non-scalar serialization
**Issue:** Returns inconsistent output for arrays/maps between yq (YAML multi-line) and Python (Python repr). For fields like `testing.required_suites`, callers may receive `- a\n- b` vs `['a', 'b']`.

**Fix:** Define stable serialization for non-scalars (recommend JSON). Ensure both yq and Python paths produce identical output. Add a test covering at least one list-valued preference field.

**Files:** `/Users/pedro/Developer/xgh/lib/preferences.sh` — in `_pref_read_yaml()` function

---

## Instructions

1. Fix only what the reviewer flagged — no scope creep.
2. Test locally if possible (especially the shell strictness and yq escaping).
3. Commit and push when done.
4. After push, Copilot will auto-re-review.

**CRITICAL:** NEVER use `@copilot` in any comments or commits — reviewer list cycle is the only safe re-request method.
