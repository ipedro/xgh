# Phase 2: Validate + Observe

> Preferences become enforceable. Hooks validate before, observe after, diagnose on failure.

**Date:** 2026-03-26
**Status:** Draft
**Scope:** 3 epics expanding the hook lifecycle from Phase 1
**Depends on:** Phase 1 (Foundation + Inject) — merged as PR #129

---

## 1. Design Decisions

Locked during brainstorming with FOR/AGAINST adversarial agents:

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | Scope | 3 epics (2.1-2.3), Epic 2.4 (PermissionRequest) deferred to Phase 4 | 2.1-2.3 form tight validate/observe/diagnose loop; 2.4 is a different concern (policy gating) |
| 2 | Validation severity | Block safety-critical, warn conventions, configurable per-check | Progressive enforcement — don't block adoption with false positives |
| 3 | Drift detection | Diff-aware (leaf-value), no schema validation | Report what changed; PreToolUse catches invalid values downstream |
| 4 | Diagnosis delivery | `additionalContext` only (human-readable) | YAGNI on structured JSON — Claude is the consumer, not code |
| 5 | Provider scope | GitHub-only, no abstraction | Can't design correct provider interface without a second provider |
| 6 | Success criteria | All 3 hooks + tests + validation skill expanded, dogfood via /xgh-ship-prs | B+ — natural dogfooding when shipping Phase 2's own PR |
| 7 | Architecture | Approach A (extend-in-place) + `lib/severity.sh` extraction | YAGNI on shared validation library; severity is a separate concern from preferences |

---

## 2. Epic 2.1: PreToolUse Full Validation

**File:** `hooks/pre-tool-use-preferences.sh` (expand existing)
**Matcher:** `Bash`

### New Checks

| Check | Trigger Patterns | Default Severity |
|-------|-----------------|------------------|
| Branch naming | `git checkout -b`, `git switch -c` | warn |
| Protected branch | `git push` to protected ref, `git commit` on protected ref | block |
| Commit format | `git commit -m`, `git commit --message` | warn |

Phase 1 checks (merge method, force-push) are **replaced** by severity-aware versions — same logic, but now routed through `_severity_resolve` so teams can configure them as `block` or `warn`.

### Severity Resolution

New file `lib/severity.sh` (~20 lines):

```bash
_severity_resolve(domain, check_name) → "block" | "warn"
```

Reads `preferences.<domain>.checks.<check_name>.severity` from project.yaml. Falls back to hardcoded defaults:

| Check | Default |
|-------|---------|
| `protected_branch` | block |
| `force_push` | block |
| `merge_method` | block |
| `branch_naming` | warn |
| `commit_format` | warn |

### Hook Flow (expanded)

1. Parse command from stdin JSON (existing jq extraction)
2. Match against check patterns (regex on command string, `.*` lookahead for flag ordering)
3. For each match: read preference value, compare against command, call `_severity_resolve`
4. `block` → `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}`
5. `warn` → `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "..."}}`
6. No match → exit 0

### project.yaml Schema Additions

Under `preferences.vcs`:

```yaml
preferences:
  pr:
    checks:
      merge_method: { severity: block }
  vcs:
    branch_naming: "^(feat|fix|docs|chore)/"
    commit_format: "^(feat|fix|docs|chore|refactor|test|ci)(\\(.+\\))?: .+"
    branches:
      main:
        protected: true
      master:
        protected: true
    checks:
      branch_naming: { severity: warn }
      protected_branch: { severity: block }
      commit_format: { severity: warn }
      force_push: { severity: block }
```

Phase 2 introduces a new `preferences.vcs.branches.<name>` map with a `protected: true` field for protected branches; existing `preferences.pr.branches`-based hooks will be migrated to this schema — no separate flat list is added.

### Design Notes

- Trigger patterns cover aliases: `git checkout -b` AND `git switch -c`, `-m` AND `--message`
- Flag ordering handled with `.*` lookahead patterns (proven in Phase 1's force-push check)
- Multi-command strings (`&&`) — only the first match is checked. Low-priority gap (Claude rarely chains destructive commands)

---

## 3. Epic 2.2: PostToolUse Drift Detection

**File:** new `hooks/post-tool-use-preferences.sh`
**Matcher:** `Write|Edit`

### Purpose

Detect when `config/project.yaml` is directly edited mid-session. Report which preference fields changed with old → new values.

### Hook Flow

1. Extract file path from stdin JSON (`tool_input.file_path`)
2. Compare against `$PROJECT_ROOT/config/project.yaml` (absolute path, not suffix match)
3. If no match → exit 0 silently
4. If snapshot missing → write current state as baseline, output: `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "[xgh] project.yaml snapshot initialized — future edits will be tracked"}}`
5. If snapshot exists → diff leaf values at depth ≤3 (`preferences.domain.field`) between snapshot and current file
6. Output changed fields: `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "config/project.yaml changed: preferences.vcs.merge_method: squash → merge, preferences.pr.reviewers added"}}`
7. Update snapshot for next comparison

### Snapshot Strategy

- **Path:** `$TMPDIR/xgh-$SESSION_ID-project-yaml.yaml`
- **Seeded by:** `session-start-preferences.sh` (add ~5 lines at end of existing hook)
- **Session ID:** extracted from stdin JSON `session_id` field. Guard against empty — fallback to `$$` (PID) + epoch.
- **Missing snapshot:** PostToolUse writes current state as baseline (not silent — emits initialization message)

### Diff Implementation

- YAML leaf-value comparison via yq or Python (field-level, not line-level)
- Depth capped at 3 levels (`preferences.domain.field`)
- No schema validation — only reports what changed
- yq path: `yq -o=json` both files, diff JSON keys
- Python fallback: `yaml.safe_load` both files, recursive key comparison

---

## 4. Epic 2.3: PostToolUseFailure Diagnosis

**File:** new `hooks/post-tool-use-failure-preferences.sh`
**Matcher:** `Bash`

### Purpose

Parse `gh` CLI stderr on failure and inject a targeted fix suggestion via `additionalContext`.

### Diagnosis Patterns

| Pattern | Command match | Stderr signal | Diagnosis |
|---------|--------------|---------------|-----------|
| Merge method mismatch | `gh pr merge` | `"merge_method"` | "Merge failed — repo requires X but command used Y. Check `preferences.pr.merge_method`" |
| Stale/wrong reviewer | `--add-reviewer` in command | `"Could not resolve"` | "Reviewer not found — verify `preferences.pr.reviewers` and bot installation" |
| Wrong repo/fork | any `gh` command | `"Could not resolve to a Repository"` | "Repository not found — verify `preferences.pr.repo` matches remote" |
| Auth required | any `gh` command | `"authentication"` or `"auth login"` | "GitHub auth required — run `gh auth login` or check your token" |

### Hook Flow

1. Extract command and error from stdin JSON (`tool_input.command`, defensive extraction of stderr from `tool_response`)
2. Check if `gh` appears as a word boundary in the command (not just prefix — handles `GH_TOKEN=x gh ...`)
3. If no `gh` → exit 0
4. Match stderr against patterns, requiring BOTH command context AND stderr signal (eliminates false positives)
5. If match: read relevant preference from project.yaml, build human-readable diagnosis
6. Output `{"hookSpecificOutput": {"hookEventName": "PostToolUseFailure", "additionalContext": "<diagnosis>"}}`
7. No match → exit 0 (fail-open)

### Design Notes

- **String matching, not regex** — `gh` stderr messages are stable and specific
- **Dual-match required** — both command pattern AND stderr pattern must match (e.g., reviewer diagnosis requires `--add-reviewer` in command AND `"Could not resolve"` in stderr)
- **Fail-open** — unrecognized failures exit silently rather than guessing wrong
- **`tool_response` shape** — must verify actual JSON structure during implementation. Defensive extraction: check `tool_response.stderr`, `tool_response.output`, and flat `tool_response`
- **`hookEventName`** — `"PostToolUseFailure"` (not `"PostToolUse"`)

---

## 5. Shared Infrastructure

### 5a: `lib/severity.sh` (new)

```bash
#!/usr/bin/env bash
# lib/severity.sh — Severity resolution for preference checks
# Sourced by pre-tool-use-preferences.sh only.
# Requires: lib/preferences.sh must be sourced first (provides _pref_read_yaml).

# Strict mode guard — only when executed directly, not when sourced.
# (Matches convention used in other lib/ files.)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

# Hardcoded defaults (safety=block, convention=warn)
declare -A _SEVERITY_DEFAULTS=(
  [protected_branch]=block
  [force_push]=block
  [merge_method]=block
  [branch_naming]=warn
  [commit_format]=warn
)

_severity_resolve() {
  local domain="$1" check_name="$2"
  local configured
  # _pref_read_yaml is provided by lib/preferences.sh (must be sourced first)
  configured=$(_pref_read_yaml "preferences.${domain}.checks.${check_name}.severity")
  if [[ "$configured" == "block" || "$configured" == "warn" ]]; then
    echo "$configured"
  else
    echo "${_SEVERITY_DEFAULTS[$check_name]:-warn}"
  fi
}
```

### 5b: Snapshot Seeding (expand `session-start-preferences.sh`)

Add at end of existing hook (~5 lines):

```bash
# Seed project.yaml snapshot for PostToolUse drift detection
# HOOK_INPUT is set by the hook runner; read stdin if unset (e.g. direct execution).
: "${HOOK_INPUT:=}"
[[ -z "$HOOK_INPUT" ]] && HOOK_INPUT=$(cat)
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty')
[[ -z "$SESSION_ID" ]] && SESSION_ID="$$-$(date +%s)"
cp "$PROJ_YAML" "${TMPDIR:-/tmp}/xgh-${SESSION_ID}-project-yaml.yaml" 2>/dev/null || true
```

### 5c: settings.json Hook Registration

New entries (appended last in each array per coexistence contract):

```json
{
  "PostToolUse": [{
    "matcher": "Write|Edit",
    "hooks": [{
      "type": "command",
      "command": "bash hooks/post-tool-use-preferences.sh"
    }]
  }],
  "PostToolUseFailure": [{
    "matcher": "Bash",
    "hooks": [{
      "type": "command",
      "command": "bash hooks/post-tool-use-failure-preferences.sh"
    }]
  }]
}
```

Existing Phase 1 hooks (PreToolUse, SessionStart, PostCompact) remain unchanged.

---

## 6. Testing Strategy

### Per-Epic Tests

| Test file | Covers |
|-----------|--------|
| `tests/test-pre-tool-use-validation.sh` | All 5 checks (branch naming, protected branch, commit format, force-push, merge method) with block/warn severity |
| `tests/test-post-tool-use-drift.sh` | Snapshot creation, field-level diff, missing snapshot handling, non-project.yaml early exit |
| `tests/test-post-tool-use-failure-diagnosis.sh` | All 4 diagnosis patterns, dual-match requirement, fail-open on unknown errors |
| `tests/test-severity.sh` | `_severity_resolve` with configured values, missing values (fallback), invalid values (fallback) |

### Existing Tests (verify no regression)

- `tests/test-hook-ordering.sh` — verify new hooks appear last in their arrays
- `tests/test-preferences.sh` — verify new schema fields are readable
- `tests/test-session-start-preferences.sh` — verify snapshot seeding doesn't break existing output

### Validation Skill Expansion

Expand `skills/validate-project-prefs/validate-project-prefs.md` to audit Phase 2 hooks:
- Verify `checks` keys in project.yaml match known check names
- Verify `severity` values are `block` or `warn`
- Verify `protected: true` branches exist in the repo
- Verify `branch_naming` and `commit_format` are valid regex

---

## 7. Files Changed

| File | Action | Epic |
|------|--------|------|
| `hooks/pre-tool-use-preferences.sh` | Expand | 2.1 |
| `lib/severity.sh` | Create | 2.1 |
| `hooks/post-tool-use-preferences.sh` | Create | 2.2 |
| `hooks/post-tool-use-failure-preferences.sh` | Create | 2.3 |
| `hooks/session-start-preferences.sh` | Expand | 2.2 (snapshot seeding) |
| `.claude/settings.json` | Expand | 2.2, 2.3 (hook registration) |
| `config/project.yaml` | Expand | 2.1 (new schema fields) |
| `skills/_shared/references/project-preferences.md` | Expand | All (document new fields) |
| `skills/validate-project-prefs/validate-project-prefs.md` | Expand | All (audit Phase 2 hooks) |
| `tests/test-pre-tool-use-validation.sh` | Create | 2.1 |
| `tests/test-post-tool-use-drift.sh` | Create | 2.2 |
| `tests/test-post-tool-use-failure-diagnosis.sh` | Create | 2.3 |
| `tests/test-severity.sh` | Create | 2.1 |

---

## 8. Out of Scope

- **Epic 2.4 (PermissionRequest policy hook)** — deferred to Phase 4 (Route + Extend)
- **Provider abstraction** — GitHub-only; no multi-provider support
- **Structured JSON diagnosis logs** — human-readable `additionalContext` only
- **Schema validation in drift detection** — reports changes, doesn't validate values
- **Auto-remediation** — hooks suggest fixes, never auto-apply

---

## 9. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `session_id` not in SessionStart JSON | Medium | Snapshot filename collision | Fallback to PID + epoch |
| `tool_response` shape varies for PostToolUseFailure | Medium | Diagnosis silently never fires | Defensive extraction, verify during implementation |
| `gh` stderr messages change across versions | Low | False negatives in diagnosis | String patterns are stable; test against current gh version |
| Regex patterns in project.yaml have syntax errors | Medium | PreToolUse check silently fails | Validation skill audits regex validity |
| TMPDIR not shared across hook subprocesses | Low | Snapshot invisible to PostToolUse | Document assumption; fallback to `.xgh/run/` if needed |

---

*Spec written: 2026-03-26*
*Depends on: Phase 1 spec (2026-03-25-declarative-preferences-lifecycle-design.md)*
