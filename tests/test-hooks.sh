#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  if ! grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 still contains '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_output() {
  local output
  output=$(bash "$1")
  if python3 - "$output" <<'PY'
import json
import sys
json.loads(sys.argv[1])
PY
  then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 did not emit valid JSON"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local output
  output=$(bash "$1")
  if [[ "$output" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected output from $1 to contain '$2'"
    FAIL=$((FAIL + 1))
  fi
}

# ── Basic file existence ──────────────────────────────────
assert_file_exists "plugin/hooks/session-start.sh"
assert_file_exists "plugin/hooks/prompt-submit.sh"

assert_not_contains "plugin/hooks/session-start.sh" "placeholder"
assert_not_contains "plugin/hooks/prompt-submit.sh" "placeholder"
assert_not_contains "plugin/hooks/session-start.sh" "not yet implemented"

# ── session-start: structured JSON output ─────────────────
# Create a temp context tree with mock .md files
TMPDIR_CT=$(mktemp -d)
trap "rm -rf $TMPDIR_CT" EXIT

mkdir -p "$TMPDIR_CT/backend/auth"
mkdir -p "$TMPDIR_CT/frontend"
mkdir -p "$TMPDIR_CT/_archived"

cat > "$TMPDIR_CT/backend/auth/jwt-patterns.md" << 'MDEOF'
---
title: JWT Patterns
importance: 92
maturity: core
---
Use short-lived access tokens.
Rotate refresh tokens on each use.
Store tokens in httpOnly cookies.
MDEOF

cat > "$TMPDIR_CT/frontend/state-management.md" << 'MDEOF'
---
title: State Management
importance: 80
maturity: validated
---
Prefer server state over client state.
Use React Query for server data.
Keep local state minimal.
MDEOF

cat > "$TMPDIR_CT/_archived/old-stuff.md" << 'MDEOF'
---
title: Old Stuff
importance: 99
maturity: core
---
Should be excluded from results.
MDEOF

cat > "$TMPDIR_CT/_index.md" << 'MDEOF'
---
title: Index
importance: 100
maturity: core
---
Should be excluded.
MDEOF

# Run session-start with the temp context tree
SS_OUTPUT=$(XGH_CONTEXT_TREE="$TMPDIR_CT" XGH_BRIEFING="off" bash plugin/hooks/session-start.sh)

# Validate JSON and keys
SS_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    keys = set(d.keys())
    required = {'result', 'contextFiles', 'decisionTable', 'briefingTrigger'}
    if required.issubset(keys):
        print('yes')
    else:
        print('no:missing:' + str(required - keys))
except Exception as e:
    print('no:' + str(e))
" "$SS_OUTPUT")
assert_eq "session-start has required keys" "$SS_VALID" "yes"

# Validate contextFiles is array of objects with correct keys
SS_CF_VALID=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
files = d.get('contextFiles', [])
if not isinstance(files, list) or len(files) == 0:
    print('no:empty-or-not-list')
    sys.exit(0)
required_keys = {'path', 'title', 'importance', 'maturity', 'excerpt'}
for f in files:
    if not required_keys.issubset(set(f.keys())):
        print('no:missing-keys:' + str(required_keys - set(f.keys())))
        sys.exit(0)
print('yes')
" "$SS_OUTPUT")
assert_eq "contextFiles has correct structure" "$SS_CF_VALID" "yes"

# Validate decisionTable is array of strings
SS_DT_VALID=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
dt = d.get('decisionTable', [])
if isinstance(dt, list) and len(dt) > 0 and all(isinstance(s, str) for s in dt):
    print('yes')
else:
    print('no')
" "$SS_OUTPUT")
assert_eq "decisionTable is array of strings" "$SS_DT_VALID" "yes"

# Validate briefingTrigger is always full (no env var gate)
SS_BT=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('briefingTrigger', ''))
" "$SS_OUTPUT")
assert_eq "briefingTrigger is always full" "$SS_BT" "full"

# Validate _archived and _index.md are excluded
SS_NO_ARCHIVED=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
paths = [f['path'] for f in d.get('contextFiles', [])]
has_bad = any('_archived' in p or '_index.md' in p for p in paths)
print('yes' if not has_bad else 'no')
" "$SS_OUTPUT")
assert_eq "excluded _archived and _index.md" "$SS_NO_ARCHIVED" "yes"

# Validate schedulerTrigger=on by default (no env var gate)
SS_SCHED_DEFAULT=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash plugin/hooks/session-start.sh)
SS_ST_DEFAULT=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('schedulerTrigger', ''))
" "$SS_SCHED_DEFAULT")
assert_eq "schedulerTrigger default=on" "$SS_ST_DEFAULT" "on"

# Validate schedulerInstructions present by default
SS_SI=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
v = d.get('schedulerInstructions', '')
print('yes' if v and '/xgh-retrieve' in v and '/xgh-analyze' in v else 'no:' + repr(v))
" "$SS_SCHED_DEFAULT")
assert_eq "schedulerInstructions contains cron prompts" "$SS_SI" "yes"

# Validate schedulerTrigger=paused when pause file exists
PAUSE_FILE="$HOME/.xgh/scheduler-paused"
mkdir -p "$HOME/.xgh"
touch "$PAUSE_FILE"
SS_SCHED_PAUSED=$(XGH_CONTEXT_TREE="$TMPDIR_CT" bash plugin/hooks/session-start.sh)
rm -f "$PAUSE_FILE"
SS_ST_PAUSED=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('schedulerTrigger', ''))
" "$SS_SCHED_PAUSED")
assert_eq "schedulerTrigger paused when pause file exists" "$SS_ST_PAUSED" "paused"

# Validate schedulerInstructions absent (null) when paused
SS_SI_PAUSED=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print('null' if d.get('schedulerInstructions') is None else 'present')
" "$SS_SCHED_PAUSED")
assert_eq "schedulerInstructions null when paused" "$SS_SI_PAUSED" "null"

# ── prompt-submit: structured JSON output ─────────────────
PS_OUTPUT=$(PROMPT="implement a new login feature" bash plugin/hooks/prompt-submit.sh)

PS_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    if 'additionalContext' in d:
        print('yes')
    else:
        print('no:missing:additionalContext, got:' + str(list(d.keys())))
except Exception as e:
    print('no:' + str(e))
" "$PS_OUTPUT")
assert_eq "prompt-submit has additionalContext key" "$PS_VALID" "yes"

# Validate code-change context is non-empty
PS_CTX=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
print('yes' if len(ctx) > 10 else 'no')
" "$PS_OUTPUT")
assert_eq "promptIntent code-change has context" "$PS_CTX" "yes"

# Validate general prompt has additionalContext key
PS_GENERAL=$(PROMPT="what time is it?" bash plugin/hooks/prompt-submit.sh)
PS_VALID_G=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print('yes' if 'additionalContext' in d else 'no')
" "$PS_GENERAL")
assert_eq "prompt-submit general has additionalContext key" "$PS_VALID_G" "yes"

# Both hooks exit 0
bash plugin/hooks/session-start.sh > /dev/null 2>&1 && PASS=$((PASS + 1)) || { echo "FAIL: session-start.sh non-zero exit"; FAIL=$((FAIL + 1)); }
bash plugin/hooks/prompt-submit.sh > /dev/null 2>&1 && PASS=$((PASS + 1)) || { echo "FAIL: prompt-submit.sh non-zero exit"; FAIL=$((FAIL + 1)); }

# ── Context-mode enforcement hooks ────────────────────────

# Helper: create a state file with given values
create_ctx_state() {
  local reads="$1" edits="$2" ctx_calls="$3"
  local state_file="/tmp/xgh-ctx-health-test-hooks.json"
  python3 -c "
import json
json.dump({
    'reads': $reads,
    'edits': $edits,
    'ctx_calls': $ctx_calls,
    'files_read': []
}, open('$state_file', 'w'))
"
  echo "$state_file"
}

# Helper: run a hook and capture its JSON output (returns empty JSON if hook missing)
run_hook_with_state() {
  local hook_script="$1"
  local state_file="$2"
  if [[ ! -f "$hook_script" ]]; then
    echo '{}'
    return 0
  fi
  XGH_CTX_STATE_OVERRIDE="$state_file" bash "$hook_script" < /dev/null 2>/dev/null
}

# Helper: extract additionalContext from hook output
extract_context() {
  local output="$1"
  python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    if 'hookSpecificOutput' in d:
        print(d['hookSpecificOutput'].get('additionalContext', ''))
    else:
        print(d.get('additionalContext', ''))
except:
    print('')
" "$output"
}

# ── pre-read.sh tests ────────────────────────────────────

assert_file_exists "plugin/hooks/pre-read.sh"

# Test: pre-read emits valid JSON with hookSpecificOutput
PRE_READ_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$(create_ctx_state 0 0 0)")
PRE_READ_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    hso = d.get('hookSpecificOutput', {})
    if hso.get('hookEventName') == 'PreToolUse' and 'additionalContext' in hso:
        print('yes')
    else:
        print('no:' + json.dumps(d))
except Exception as e:
    print('no:' + str(e))
" "$PRE_READ_OUT")
assert_eq "pre-read emits hookSpecificOutput" "$PRE_READ_VALID" "yes"

# Test: pre-read increments reads counter
STATE_FILE=$(create_ctx_state 0 0 0)
run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE" > /dev/null
READS_AFTER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['reads'])")
assert_eq "pre-read increments reads" "$READS_AFTER" "1"

# Test: tier 1 (0-2 unedited reads) — gentle tip, no emoji escalation
STATE_FILE=$(create_ctx_state 1 0 0)
TIER1_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
TIER1_CTX=$(extract_context "$TIER1_OUT")
TIER1_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if 'ctx_execute_file' in ctx and '\U0001f6d1' not in ctx and '\u26a0\ufe0f' not in ctx else 'no:' + ctx)
" "$TIER1_CTX")
assert_eq "pre-read tier 1 is gentle tip" "$TIER1_OK" "yes"

# Test: tier 2 (3-4 unedited reads) — warning emoji
STATE_FILE=$(create_ctx_state 3 0 0)
TIER2_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
TIER2_CTX=$(extract_context "$TIER2_OUT")
TIER2_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if '\u26a0\ufe0f' in ctx else 'no:' + repr(ctx))
" "$TIER2_CTX")
assert_eq "pre-read tier 2 has warning emoji" "$TIER2_OK" "yes"

# Test: tier 3 (5+ unedited reads) — stop emoji + routing doc ref
STATE_FILE=$(create_ctx_state 5 0 0)
TIER3_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
TIER3_CTX=$(extract_context "$TIER3_OUT")
TIER3_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if '\U0001f6d1' in ctx and 'context-mode-routing' in ctx else 'no:' + repr(ctx))
" "$TIER3_CTX")
assert_eq "pre-read tier 3 has stop emoji + routing ref" "$TIER3_OK" "yes"

# Test: suppressed when ctx_calls >= 2
STATE_FILE=$(create_ctx_state 5 0 2)
SUPPRESSED_OUT=$(run_hook_with_state "plugin/hooks/pre-read.sh" "$STATE_FILE")
SUPPRESSED_CTX=$(extract_context "$SUPPRESSED_OUT")
SUPPRESSED_OK=$(python3 -c "
import sys
ctx = sys.argv[1]
print('yes' if '\U0001f6d1' not in ctx and '\u26a0\ufe0f' not in ctx else 'no:' + repr(ctx))
" "$SUPPRESSED_CTX")
assert_eq "pre-read suppressed when ctx_calls >= 2" "$SUPPRESSED_OK" "yes"

# Test: missing state file is handled gracefully
rm -f /tmp/xgh-ctx-health-test-missing.json
MISSING_OUT=$(XGH_CTX_STATE_OVERRIDE="/tmp/xgh-ctx-health-test-missing.json" bash plugin/hooks/pre-read.sh < /dev/null 2>/dev/null || echo '{}')
MISSING_VALID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print('yes' if 'hookSpecificOutput' in d else 'no')
except:
    print('no:invalid-json')
" "$MISSING_OUT")
assert_eq "pre-read handles missing state file" "$MISSING_VALID" "yes"

# ── post-edit.sh tests ───────────────────────────────────

assert_file_exists "plugin/hooks/post-edit.sh"

# Test: post-edit increments edits counter
STATE_FILE=$(create_ctx_state 3 0 0)
XGH_CTX_STATE_OVERRIDE="$STATE_FILE" bash plugin/hooks/post-edit.sh < /dev/null 2>/dev/null || true
EDITS_AFTER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['edits'])")
assert_eq "post-edit increments edits" "$EDITS_AFTER" "1"

# ── post-ctx-call.sh tests ───────────────────────────────

assert_file_exists "plugin/hooks/post-ctx-call.sh"

# Test: post-ctx-call increments ctx_calls counter
STATE_FILE=$(create_ctx_state 0 0 0)
XGH_CTX_STATE_OVERRIDE="$STATE_FILE" bash plugin/hooks/post-ctx-call.sh < /dev/null 2>/dev/null || true
CTX_AFTER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['ctx_calls'])")
assert_eq "post-ctx-call increments ctx_calls" "$CTX_AFTER" "1"

# ── session-start ctx-mode integration tests ──────────────

# Set up a fake HOME with context-mode cache to make tests deterministic
FAKE_HOME=$(mktemp -d)
mkdir -p "$FAKE_HOME/.claude/plugins/cache/context-mode"

# Test: decision table includes ctx_execute_file guidance
SS_CTX_OUT=$(HOME="$FAKE_HOME" XGH_CONTEXT_TREE="$TMPDIR_CT" bash plugin/hooks/session-start.sh)
SS_CTX_DT=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
dt = d.get('decisionTable', [])
has_ctx = any('ctx_execute_file' in s for s in dt)
print('yes' if has_ctx else 'no')
" "$SS_CTX_OUT")
assert_eq "session-start decision table mentions ctx_execute_file" "$SS_CTX_DT" "yes"

# Test: ctxModeAvailable key is present
SS_CTX_KEY=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print('yes' if 'ctxModeAvailable' in d else 'no')
" "$SS_CTX_OUT")
assert_eq "session-start has ctxModeAvailable key" "$SS_CTX_KEY" "yes"

# Clean up fake home
rm -rf "$FAKE_HOME"

# Test: schedulerInstructions mentions deep-retrieve
SS_DEEP=$(XGH_CONTEXT_TREE="$TMPDIR_CT" XGH_SCHEDULER="on" bash plugin/hooks/session-start.sh)
SS_DEEP_OK=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
si = d.get('schedulerInstructions', '')
print('yes' if '/xgh-deep-retrieve' in (si or '') else 'no')
" "$SS_DEEP")
assert_eq "schedulerInstructions mentions deep-retrieve" "$SS_DEEP_OK" "yes"

# ── prompt-submit nudge tests ────────────────────────────

# Test: nudge fires when 3+ unedited reads and 0 ctx calls
NUDGE_STATE=$(create_ctx_state 4 1 0)
PS_NUDGE_OUT=$(XGH_CTX_STATE_OVERRIDE="$NUDGE_STATE" PROMPT="hello" bash plugin/hooks/prompt-submit.sh)
PS_NUDGE_CTX=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
print('yes' if 'Session health' in ctx else 'no')
" "$PS_NUDGE_OUT")
assert_eq "prompt-submit nudge fires on high unedited reads" "$PS_NUDGE_CTX" "yes"

# Test: nudge suppressed when ctx_calls >= 2
NO_NUDGE_STATE=$(create_ctx_state 5 0 3)
PS_NO_NUDGE=$(XGH_CTX_STATE_OVERRIDE="$NO_NUDGE_STATE" PROMPT="hello" bash plugin/hooks/prompt-submit.sh)
PS_NO_NUDGE_CTX=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
ctx = d.get('additionalContext', '')
print('yes' if 'Session health' not in ctx else 'no')
" "$PS_NO_NUDGE")
assert_eq "prompt-submit nudge suppressed when ctx active" "$PS_NO_NUDGE_CTX" "yes"

echo ""
echo "Hooks test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
