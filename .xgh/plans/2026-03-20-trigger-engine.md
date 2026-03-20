# Trigger Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an IFTTT-style trigger engine that evaluates provider inbox items, local bash commands, and cron schedules against user-defined YAML rules, then executes notify/create/mutate/dispatch actions with exponential backoff and action-level safety gating.

**Architecture:** Three event sources (provider inbox items, local bash commands via PostToolUse hook, cron schedules) feed two evaluation paths: fast (post-urgency-scoring in retrieve, ~5min) and standard (post-classification in analyze, ~30min). Evaluation reads `~/.xgh/triggers/*.yaml`, enforces the global → trigger → step action_level cap, applies exponential backoff via `~/.xgh/triggers/.state.json`, deduplicates via `fired_items`, and dispatches declarative actions (notify, create_issue, create_pr, mutate, dispatch, store).

**Tech Stack:** Bash hooks (PostToolUse for local events), YAML trigger files, JSON state file, Markdown skill files (Claude reads and follows), existing lossless-claude MCP, Slack/Telegram/Gmail MCPs.

---

## File Map

**Create:**
- `skills/trigger/trigger.md` — `/xgh-trigger` management skill (list, test, silence, history)
- `commands/trigger.md` — slash command dispatcher for `/xgh-trigger`
- `hooks/post-tool-use.sh` — captures successful bash commands as `local_command` inbox items
- `triggers/examples/p0-alert.yaml` — P0 Jira issue → Slack + investigate
- `triggers/examples/pr-stale-reminder.yaml` — PR stale >24h → DM
- `triggers/examples/npm-post-publish.yaml` — npm publish → tag release + notify
- `triggers/examples/weekly-standup.yaml` — Monday 9am → dispatch /xgh-brief
- `triggers/examples/README.md` — guide to example triggers
- `tests/test-trigger.sh` — validates skill structure, schema, state model, hook

**Modify:**
- `skills/init/init.md` — create `~/.xgh/triggers/`, write default `triggers.yaml`, note PostToolUse hook setup
- `hooks/session-start.sh` — add `mkdir -p ~/.xgh/triggers` to directory bootstrap
- `skills/analyze/analyze.md` — add Step 8: standard-path trigger evaluation after classification
- `skills/retrieve/retrieve.md` — add Step 4b: fast-path trigger evaluation after urgency scoring
- `skills/schedule/schedule.md` — add schedule-event trigger evaluation pass
- `skills/track/track.md` — add trigger suggestion step after provider generation
- `skills/doctor/doctor.md` — add Check 8: trigger health (dir, global config, enabled count, last-fired)

---

## Task 1: Test foundation (TDD anchor)

**Files:**
- Create: `tests/test-trigger.sh`

- [ ] **Step 1: Write the failing test file**

```bash
#!/usr/bin/env bash
# test-trigger.sh — Validates trigger engine structure and conventions

PASS=0; FAIL=0
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

assert_file_exists() {
  if [ -f "$1" ]; then
    echo "PASS: $2"; PASS=$((PASS+1))
  else
    echo "FAIL: $2 — missing: $1"; FAIL=$((FAIL+1))
  fi
}

assert_dir_exists() {
  if [ -d "$1" ]; then
    echo "PASS: $2"; PASS=$((PASS+1))
  else
    echo "FAIL: $2 — missing dir: $1"; FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    echo "PASS: $3"; PASS=$((PASS+1))
  else
    echo "FAIL: $3 — '$2' not found in $1"; FAIL=$((FAIL+1))
  fi
}

# ── Skill + command exist ─────────────────────────────────────────────────────
assert_file_exists "$PLUGIN_DIR/skills/trigger/trigger.md"   "trigger skill exists"
assert_file_exists "$PLUGIN_DIR/commands/trigger.md"         "trigger command exists"
assert_file_exists "$PLUGIN_DIR/hooks/post-tool-use.sh"      "post-tool-use hook exists"

# ── trigger.md content ───────────────────────────────────────────────────────
TRIGGER_SKILL="$PLUGIN_DIR/skills/trigger/trigger.md"
assert_contains "$TRIGGER_SKILL" "xgh:trigger"               "trigger skill has correct name"
assert_contains "$TRIGGER_SKILL" "list"                       "trigger skill covers list command"
assert_contains "$TRIGGER_SKILL" "silence"                    "trigger skill covers silence command"
assert_contains "$TRIGGER_SKILL" "test"                       "trigger skill covers test command"
assert_contains "$TRIGGER_SKILL" "history"                    "trigger skill covers history command"
assert_contains "$TRIGGER_SKILL" '~/.xgh/triggers/'          "trigger skill references triggers dir"
assert_contains "$TRIGGER_SKILL" '.state.json'               "trigger skill references state file"
assert_contains "$TRIGGER_SKILL" "action_level"              "trigger skill documents action_level"
assert_contains "$TRIGGER_SKILL" "backoff"                   "trigger skill documents backoff"
assert_contains "$TRIGGER_SKILL" "fired_items"               "trigger skill documents dedup"

# ── post-tool-use.sh content ─────────────────────────────────────────────────
HOOK="$PLUGIN_DIR/hooks/post-tool-use.sh"
assert_contains "$HOOK" "local_command"                      "hook uses local_command source_type"
assert_contains "$HOOK" "source: local"                      "hook checks for local triggers"
assert_contains "$HOOK" '~/.xgh/triggers'                   "hook reads trigger dir"
assert_contains "$HOOK" '~/.xgh/inbox'                      "hook writes to inbox"

# ── analyze.md integration ───────────────────────────────────────────────────
ANALYZE="$PLUGIN_DIR/skills/analyze/analyze.md"
assert_contains "$ANALYZE" "trigger"                         "analyze has trigger evaluation"
assert_contains "$ANALYZE" "standard"                        "analyze references standard path"
assert_contains "$ANALYZE" "triggers.yaml"                   "analyze reads global trigger config"

# ── retrieve.md integration ──────────────────────────────────────────────────
RETRIEVE="$PLUGIN_DIR/skills/retrieve/retrieve.md"
assert_contains "$RETRIEVE" "fast"                           "retrieve has fast-path trigger evaluation"
assert_contains "$RETRIEVE" "trigger"                        "retrieve references trigger engine"

# ── init.md integration ──────────────────────────────────────────────────────
INIT="$PLUGIN_DIR/skills/init/init.md"
assert_contains "$INIT" '~/.xgh/triggers'                   "init creates triggers directory"
assert_contains "$INIT" "triggers.yaml"                      "init creates global trigger config"

# ── doctor.md integration ────────────────────────────────────────────────────
DOCTOR="$PLUGIN_DIR/skills/doctor/doctor.md"
assert_contains "$DOCTOR" "trigger"                          "doctor has trigger health check"
assert_contains "$DOCTOR" "triggers.yaml"                    "doctor checks global trigger config"

# ── track.md integration ─────────────────────────────────────────────────────
TRACK="$PLUGIN_DIR/skills/track/track.md"
assert_contains "$TRACK" "trigger"                           "track suggests triggers after provider generation"

# ── schedule.md integration ──────────────────────────────────────────────────
SCHEDULE="$PLUGIN_DIR/skills/schedule/schedule.md"
assert_contains "$SCHEDULE" "trigger"                        "schedule evaluates schedule-type triggers"
assert_contains "$SCHEDULE" "source: schedule"              "schedule references schedule event source"

# ── example triggers ─────────────────────────────────────────────────────────
assert_dir_exists  "$PLUGIN_DIR/triggers/examples"           "triggers/examples/ directory exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/README.md" "triggers examples README exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/p0-alert.yaml"          "p0-alert example exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/pr-stale-reminder.yaml" "pr-stale example exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/npm-post-publish.yaml"  "npm-post-publish example exists"
assert_file_exists "$PLUGIN_DIR/triggers/examples/weekly-standup.yaml"    "weekly-standup example exists"

# ── example trigger content ──────────────────────────────────────────────────
P0="$PLUGIN_DIR/triggers/examples/p0-alert.yaml"
assert_contains "$P0" "schema_version"                       "p0-alert has schema_version"
assert_contains "$P0" "action_level"                         "p0-alert has action_level"
assert_contains "$P0" "backoff"                              "p0-alert has backoff policy"
assert_contains "$P0" "fired_items"                          "no: fired_items is in .state.json not YAML"  # skip, state only

NPM="$PLUGIN_DIR/triggers/examples/npm-post-publish.yaml"
assert_contains "$NPM" "source: local"                       "npm-post-publish uses local source"
assert_contains "$NPM" "npm publish"                         "npm-post-publish matches npm command"

STANDUP="$PLUGIN_DIR/triggers/examples/weekly-standup.yaml"
assert_contains "$STANDUP" "source: schedule"                "weekly-standup uses schedule source"
assert_contains "$STANDUP" "cron"                            "weekly-standup has cron expression"

# ── session-start.sh integration ─────────────────────────────────────────────
SESSION_START="$PLUGIN_DIR/hooks/session-start.sh"
assert_contains "$SESSION_START" '~/.xgh/triggers'          "session-start creates triggers dir"

# ── Result ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/test-trigger.sh
```

Expected: Many FAILs — none of the files exist yet.

- [ ] **Step 3: Commit test baseline**

```bash
git add tests/test-trigger.sh
git commit -m "test(trigger): add test-trigger.sh as TDD anchor"
```

---

## Task 2: `/xgh-trigger` skill and command

**Files:**
- Create: `skills/trigger/trigger.md`
- Create: `commands/trigger.md`

- [ ] **Step 1: Create the trigger skill**

Create `skills/trigger/trigger.md`:

```markdown
---
name: xgh:trigger
description: Manage the xgh trigger engine — list triggers, test them against inbox items, silence noisy ones, view firing history
type: flexible
triggers:
  - when invoked via /xgh-trigger command
mcp_dependencies: []
---

# context-mode routing

Use `ctx_execute_file` for reading trigger YAML files (analysis only).
Use `Read` only for files you are about to edit.
Use `ctx_execute(language: "shell")` for shell commands with >5 lines output.

---

# /xgh-trigger — Trigger Engine Management

Manage xgh triggers. Reads `~/.xgh/triggers/*.yaml` (user-defined rules) and
`~/.xgh/triggers/.state.json` (firing state: cooldowns, counts, silence).

## Sub-commands

### list

Show all triggers with status at a glance.

1. Read `~/.xgh/triggers.yaml` (global config: enabled, action_level, cooldown).
   If missing: warn "⚠ No global config — run /xgh-init to create ~/.xgh/triggers.yaml"
2. Read all `~/.xgh/triggers/*.yaml` files (skip `.state.json`).
3. Read `~/.xgh/triggers/.state.json` (if exists) for last_fired and silenced_until.
4. Output as a markdown table:

| Name | Source | Path | Level | Enabled | Last Fired | Status |
|------|--------|------|-------|---------|-----------|--------|
| p0-alert | jira | standard | autonomous | ✅ | 2h ago | active |
| pr-stale | github | fast | notify | ✅ | never | active |
| npm-publish | local | standard | create | ❌ | — | disabled |
| weekly-standup | schedule | standard | notify | ✅ | 3d ago | silenced until 09:00 |

5. Below the table, print global config summary:
   `Global: action_level=create | cooldown=5m | fast_path=true | triggers enabled=true`

### test <name>

Dry-run a trigger against the latest inbox item that would match its `when:` conditions.

1. Load the named trigger file from `~/.xgh/triggers/<name>.yaml`.
2. Scan `~/.xgh/inbox/*.md` for items NOT in `processed/`.
3. Find the newest item matching all `when:` conditions (source, type, project, match:).
   - For `source: local` triggers: look for items with `source_type: local_command`.
   - For `source: schedule` triggers: evaluate the cron expression against now.
4. If no matching item: "No matching inbox item found for this trigger right now."
5. If found: show what would fire:
   ```
   🧪 DRY RUN — p0-alert
   Matched: ~/.xgh/inbox/2026-03-20T14-30-00Z_jira_MOBILE-1234.md
     title: "Login crash on iOS 17"
     urgency_score: 95

   Would execute 2 steps:
     Step 1 [notify/slack]: Post to #incidents — "P0: Login crash on iOS 17 — https://..."
     Step 2 [autonomous/dispatch]: /xgh-investigate "https://jira.../MOBILE-1234"
       (requires action_level: autonomous — currently allowed ✅)

   Cooldown state: never fired — would fire immediately
   ```
6. Do NOT execute any actions.

### silence <name> <duration>

Suppress a trigger temporarily.

Accepted durations: `30m`, `2h`, `1d`, etc.

1. Load `~/.xgh/triggers/.state.json` (create if missing: `{}`).
2. Calculate `silenced_until` = now + duration (ISO 8601 timestamp).
3. Write `"silenced_until": "<timestamp>"` under the trigger name in .state.json.
4. Confirm: "✅ p0-alert silenced until 2026-03-21T16:00:00Z"

### history <name>

Show the last 10 firing events for a trigger.

1. Read `.state.json` for this trigger: `last_fired`, `fire_count`, `current_cooldown_seconds`, `fired_items`.
2. Output:
   ```
   📋 p0-alert — firing history

   Total fires: 7
   Last fired: 2026-03-20T14:30:00Z (2h ago)
   Current cooldown: 20 min (exponential, base 5m, max 6h)
   Silenced: no

   Recent items fired for (last 5):
     2026-03-20T14-30-00Z_p0_jira_MOBILE-1234.md
     2026-03-19T09-15-00Z_p0_jira_MOBILE-1198.md
     2026-03-18T22-00-00Z_p0_jira_MOBILE-1156.md
   ```

## Trigger Evaluation Logic (reference)

Used by analyze and retrieve skills — documented here for consistency.

### Matching

Check all `when:` fields. ALL must match for a trigger to fire:
- `source:` — matches `item.source` field in inbox frontmatter. `*` matches any.
- `type:` — matches `item.type` from analyze classification. NOT available on fast path.
- `project:` — matches `item.project` from ingest.yaml. `*` matches any.
- `match:` — regex patterns on item frontmatter fields. `!` prefix = exclude.
- `command:` — regex matched against `command:` field (local events only).
- `exit_code:` — exact match against `exit_code:` field (local events only).
- `cron:` — matched against current time (schedule events only).

### Cooldown / backoff check

Before firing, check `.state.json` for this trigger:
1. If `silenced_until` is set and in the future → skip.
2. If `last_fired` is set: compute elapsed = now - last_fired (seconds).
3. Compute `current_cooldown_seconds` by backoff strategy:
   - `none`: 0 (always fire)
   - `fixed`: the `cooldown:` value
   - `exponential`: base_cooldown × 2^(fire_count - 1), capped at `max_cooldown`
4. If elapsed < current_cooldown_seconds → skip.
5. Check `reset_after:` — if elapsed > reset_after, reset fire_count to 0 first.

### Dedup check

Check `fired_items` array in `.state.json`. If the inbox item's filename is already
in `fired_items` → skip (prevents re-firing on the same item across cycles).

### Action level enforcement

For each `then:` step:
1. Determine step's `action_level:` (or inherit from trigger, or inherit from global default `notify`).
2. If step level > trigger `action_level:` cap → REFUSE, log warning, skip step.
3. If step level > global `action_level:` cap → REFUSE, log warning, skip step.

Level order: `notify` < `create` < `mutate` < `autonomous`

### Template variable expansion

Available in `message:`, `args:`, `title:`, `body:` fields in `then:` steps:
`{item.title}`, `{item.url}`, `{item.source}`, `{item.type}`, `{item.project}`,
`{item.author}`, `{item.timestamp}`, `{item.urgency_score}`, `{item.repo}`,
`{item.number}`, `{item.key}`, `{item.description}`, `{item.summary}`, `{item.slug}`,
`{item.version}`, `{item.severity}`, `{item.chat_id}`, `{item.channel_id}`.

In `run:` blocks: use `$ITEM_TITLE`, `$ITEM_URL`, `$ITEM_SOURCE`, `$ITEM_TYPE`,
`$ITEM_PROJECT`, `$ITEM_AUTHOR`, `$ITEM_TIMESTAMP`, `$ITEM_URGENCY`, `$ITEM_REPO`,
`$ITEM_NUMBER`, `$ITEM_KEY`, `$ITEM_VERSION`, `$ITEM_SEVERITY`.
Template `{item.*}` vars are NOT expanded in `run:` — prevents shell injection.

In `on_complete:` after a `dispatch:` step: `{result.summary}`, `{result.status}`,
`{result.files}`, `{result.commit}`, `{result.pr_url}`.

### After firing

Update `.state.json`:
```json
{
  "p0-alert": {
    "last_fired": "<ISO timestamp>",
    "fire_count": 4,
    "current_cooldown_seconds": 2400,
    "silenced_until": null,
    "fired_items": ["<filename>", "...up to 100, oldest evicted"]
  }
}
```

### Step error handling

Per-step `on_error:` (or trigger-level default):
- `continue` (default): log error, proceed to next step
- `abort`: log error, skip remaining steps
- `retry`: retry once after 5s, then continue
```

- [ ] **Step 2: Create the trigger command**

Create `commands/trigger.md`:

```markdown
# /xgh-trigger — Trigger Engine Management

Invokes the `xgh:trigger` skill.

## Usage

```
/xgh-trigger list
/xgh-trigger test <name>
/xgh-trigger silence <name> <duration>
/xgh-trigger history <name>
```

## What it does

Reads `~/.xgh/triggers/*.yaml` and `~/.xgh/triggers/.state.json`.
- `list` — table of all triggers with status and last-fired time
- `test <name>` — dry-run against latest matching inbox item (no actions executed)
- `silence <name> <duration>` — suppress trigger temporarily (30m, 2h, 1d)
- `history <name>` — show firing history and current backoff state
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep -E "PASS|FAIL"
```

Expected: skill and command assertions pass; many others still failing.

- [ ] **Step 4: Commit**

```bash
git add skills/trigger/trigger.md commands/trigger.md
git commit -m "feat(trigger): add /xgh-trigger management skill and command"
```

---

## Task 3: Trigger evaluation in analyze (standard path)

**Files:**
- Modify: `skills/analyze/analyze.md`

This task adds the trigger evaluation step at the END of the analyze skill, after content classification and memory storage.

- [ ] **Step 1: Read the file to find the final section**

```bash
grep -n "Step\|##\|Output discipline" skills/analyze/analyze.md | tail -30
```

Note the line number of the last numbered Step (will be something like "Step 7" for memory storage).
Note the line number of the "Output discipline" section.

- [ ] **Step 2: Insert the new step before "Output discipline"**

Find the exact text just before the "Output discipline" section in `skills/analyze/analyze.md` and insert this block:

```markdown
## Step 8: Standard-path trigger evaluation

After classification and memory storage, evaluate standard-path triggers.

**Skip this step entirely if:**
- `~/.xgh/triggers.yaml` does not exist (triggers not configured)
- `~/.xgh/triggers.yaml` has `enabled: false`
- No files exist in `~/.xgh/triggers/` (no triggers defined)

**Procedure:**

1. Read `~/.xgh/triggers.yaml` (global config). Note `action_level`, `cooldown`, `fast_path`.
2. Read all `~/.xgh/triggers/*.yaml` files (skip `.state.json`).
   Filter to triggers where `path: standard` OR `path:` is not set (default = standard).
   Skip `source: schedule` triggers (handled by schedule skill).
3. Read `~/.xgh/triggers/.state.json` (or `{}` if missing).
4. For each classified inbox item (use `ctx_execute_file` to read frontmatter):
   For each standard-path trigger:
   a. **Match check:** Evaluate all `when:` fields against the item.
      - `source:` matches item frontmatter `source:` field (`*` = any)
      - `type:` matches item frontmatter `type:` from classification (`*` = any)
      - `project:` matches item frontmatter `project:` (`*` = any)
      - `match:` regex patterns on item fields — `!` prefix means exclude
   b. **Cooldown check:** See xgh:trigger evaluation logic (cooldown / backoff / dedup checks).
      If any check fails → skip.
   c. **Dedup check:** If item filename in `fired_items` array → skip.
   d. **Execute steps:** For each `then:` step, enforce action_level cap, then execute.
      Use declarative actions (notify, create_issue, dispatch) via appropriate MCP tools.
      Inline `run:` blocks: execute via `ctx_execute(language: "shell", code: ...)` with
      all `$ITEM_*` env vars set. Only stdout enters context.
   e. **Update state:** Write updated `.state.json` after each trigger fires.
5. Log: `Trigger engine: evaluated N triggers against M items — K fired`
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep "analyze"
```

Expected: analyze assertions pass.

- [ ] **Step 4: Commit**

```bash
git add skills/analyze/analyze.md
git commit -m "feat(trigger): add standard-path trigger evaluation to analyze skill"
```

---

## Task 4: Fast-path trigger evaluation in retrieve

**Files:**
- Modify: `skills/retrieve/retrieve.md`

Adds fast-path trigger evaluation after Step 4 (urgency scoring). Fast path fires on urgency_score + keyword matches — before classification runs.

- [ ] **Step 1: Read file to find Step 4 location**

```bash
grep -n "Step 4\|urgency\|Step 5" skills/retrieve/retrieve.md | head -20
```

Note the line range of Step 4 and the start of Step 5 (or final section).

- [ ] **Step 2: Insert fast-path block after Step 4**

Find the text that ends the urgency scoring step and insert this block immediately after:

```markdown
## Step 4b: Fast-path trigger evaluation

Evaluate triggers where urgency warrants immediate action — before analyze runs.

**Skip this step entirely if:**
- `~/.xgh/triggers.yaml` does not exist or has `enabled: false`
- `~/.xgh/triggers.yaml` has `fast_path: false`
- No `~/.xgh/triggers/*.yaml` files have `path: fast`

**Procedure:**

1. Read only triggers with `path: fast` from `~/.xgh/triggers/*.yaml`.
   Skip `source: local` and `source: schedule` triggers.
2. For each newly scored inbox item with `urgency_score >= 70`:
   For each fast-path trigger:
   a. **Match check:**
      - `source:` matches item's `source:` field
      - `when.urgency_score:` threshold — evaluate if specified (e.g., `>= 90`)
      - `match:` keyword patterns on item title/content (regex)
      - NOTE: `when.type:` is NOT checked — classification has not run yet
   b. **Cooldown + dedup check:** same logic as standard path (see xgh:trigger skill).
   c. **Execute steps:** same execution as standard path.
   d. **Update state.**
3. Log: `Fast-path triggers: N evaluated, K fired`

Fast-path triggers should use `when.match:` patterns and `when.urgency_score:` thresholds,
NOT `when.type:` (type is only available after analyze classification).
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep "retrieve"
```

Expected: retrieve assertions pass.

- [ ] **Step 4: Commit**

```bash
git add skills/retrieve/retrieve.md
git commit -m "feat(trigger): add fast-path trigger evaluation to retrieve skill"
```

---

## Task 5: Init setup — directories, global config, PostToolUse hook note

**Files:**
- Modify: `skills/init/init.md`
- Modify: `hooks/session-start.sh`

- [ ] **Step 1: Find the mkdir block in init.md**

```bash
grep -n "mkdir\|~/.xgh\|inbox\|user_providers" skills/init/init.md | head -20
```

Find the line that creates `~/.xgh/user_providers` (last entry in the mkdir block).

- [ ] **Step 2: Add triggers dir to the mkdir block**

In `skills/init/init.md`, find the mkdir block that includes `~/.xgh/user_providers` and append `~/.xgh/triggers` to it. The exact text to add after the `user_providers` line:

```
mkdir -p ~/.xgh/triggers
```

- [ ] **Step 3: Add global triggers.yaml creation**

After the mkdir block in `skills/init/init.md`, find a good location (near the end of Step 0 or as a new sub-step 0d) and insert:

```markdown
#### Step 0d: Initialize trigger global config

If `~/.xgh/triggers.yaml` does not exist, create it with defaults:

```yaml
# ~/.xgh/triggers.yaml — Global trigger engine config
# Edit this to change what the trigger engine is allowed to do.

enabled: true
action_level: notify       # max allowed: notify | create | mutate | autonomous
fast_path: true            # evaluate critical triggers during retrieve (5min path)
cooldown: 5m               # default cooldown for all triggers
```

> This file is NEVER touched by plugin updates. It is yours.
> To disable all triggers: set `enabled: false`.
> To allow issue/PR creation: set `action_level: create`.
> To allow agent dispatch: set `action_level: autonomous`.

Also note: To capture local bash command events (for `source: local` triggers),
the PostToolUse hook in `hooks/post-tool-use.sh` must be registered. Run `/xgh-setup`
or add it to your Claude Code settings manually.
```

- [ ] **Step 4: Add mkdir to session-start.sh**

In `hooks/session-start.sh`, find the section that creates `~/.xgh/` subdirectories (near the top, where `mkdir -p ~/.xgh/inbox/processed` or similar lines appear). Add:

```bash
mkdir -p ~/.xgh/triggers
```

alongside the other mkdir commands.

- [ ] **Step 5: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep -E "init|session-start|triggers dir|global config"
```

Expected: init and session-start assertions pass.

- [ ] **Step 6: Commit**

```bash
git add skills/init/init.md hooks/session-start.sh
git commit -m "feat(trigger): init creates ~/.xgh/triggers/ and default triggers.yaml"
```

---

## Task 6: PostToolUse hook for local command events

**Files:**
- Create: `hooks/post-tool-use.sh`

This hook runs after every Bash tool call. It writes a lightweight inbox item when a bash command matches a `source: local` trigger's `command:` pattern.

- [ ] **Step 1: Write the hook**

Create `hooks/post-tool-use.sh`:

```bash
#!/usr/bin/env bash
# PostToolUse hook — capture local command events for xgh trigger engine
#
# Called by Claude Code after each tool use.
# Receives JSON on stdin: { tool_name, tool_input, tool_response }
#
# If any ~/.xgh/triggers/*.yaml has `source: local`, checks whether the
# command matches. Writes a local_command inbox item if so.

set -euo pipefail

TRIGGER_DIR="$HOME/.xgh/triggers"
INBOX_DIR="$HOME/.xgh/inbox"

# Fast exit: no triggers dir = nothing to do
[ -d "$TRIGGER_DIR" ] || exit 0

# Fast exit: no local triggers = nothing to do
if ! grep -ql "source: local" "$TRIGGER_DIR"/*.yaml 2>/dev/null; then
  exit 0
fi

# Read hook JSON from stdin
HOOK_JSON=$(cat 2>/dev/null || echo "{}")
[ -n "$HOOK_JSON" ] || exit 0

# Only process Bash tool calls
TOOL_NAME=$(echo "$HOOK_JSON" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Bash" ] || exit 0

# Extract command and exit code
COMMAND=$(echo "$HOOK_JSON" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" \
  2>/dev/null || echo "")
EXIT_CODE=$(echo "$HOOK_JSON" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_response',{}).get('exit_code',0))" \
  2>/dev/null || echo "0")

[ -n "$COMMAND" ] || exit 0

# Check if any local trigger's command pattern matches
MATCHED=false
while IFS= read -r -d '' TRIGGER_FILE; do
  # Read command pattern from trigger YAML
  CMD_PATTERN=$(grep -A1 "^  command:" "$TRIGGER_FILE" 2>/dev/null | tail -1 | sed 's/.*: *"//' | sed 's/".*//' || echo "")
  [ -n "$CMD_PATTERN" ] || continue

  # Check exit_code expectation (default: 0)
  EXPECTED_EXIT=$(grep "exit_code:" "$TRIGGER_FILE" 2>/dev/null | head -1 | awk '{print $2}' || echo "0")
  [ "$EXIT_CODE" = "$EXPECTED_EXIT" ] || continue

  # Match command against pattern
  if echo "$COMMAND" | grep -qE "$CMD_PATTERN" 2>/dev/null; then
    MATCHED=true
    break
  fi
done < <(find "$TRIGGER_DIR" -name "*.yaml" -not -name ".*" -print0 2>/dev/null)

[ "$MATCHED" = "true" ] || exit 0

# Write inbox item
mkdir -p "$INBOX_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
SAFE_CMD=$(echo "$COMMAND" | tr ' /()[]{}' '_' | head -c 40)
INBOX_FILE="$INBOX_DIR/${TIMESTAMP}_local_command_${SAFE_CMD}.md"

TITLE=$(echo "$COMMAND" | head -c 80)

cat > "$INBOX_FILE" << YAML
---
source_type: local_command
source: local
command: "$COMMAND"
exit_code: $EXIT_CODE
title: "$TITLE"
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
urgency_score: 50
---

Local command executed successfully.
Command: $COMMAND
Exit code: $EXIT_CODE
YAML

exit 0
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x hooks/post-tool-use.sh
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep "hook\|post-tool"
```

Expected: hook assertions pass.

- [ ] **Step 4: Commit**

```bash
git add hooks/post-tool-use.sh
git commit -m "feat(trigger): add PostToolUse hook for local command event capture"
```

---

## Task 7: Doctor health check

**Files:**
- Modify: `skills/doctor/doctor.md`

- [ ] **Step 1: Find the last Check in doctor.md**

```bash
grep -n "^## Check\|^### Check" skills/doctor/doctor.md | tail -5
```

Note the number of the last check and the line where the next section begins (Step 10 or Output discipline).

- [ ] **Step 2: Insert Check 8 before the final step**

Find the text starting "## Step 10" (or the output discipline section) and insert this block immediately before it:

```markdown
## Check 8: Trigger engine

Validate the trigger engine configuration and runtime state.

1. **Global config** — check `~/.xgh/triggers.yaml`:
   - ✅ exists and `enabled: true` and valid `action_level:`
   - ⚠️ exists but `enabled: false` — triggers are globally disabled
   - ❌ missing — run `/xgh-init` to create it

2. **Trigger directory** — check `~/.xgh/triggers/`:
   - Count `.yaml` files (exclude `.state.json`)
   - Count enabled triggers (`enabled: true`) vs disabled
   - ✅ `N triggers (M enabled)`
   - ⚠️ `0 triggers defined` — no triggers yet (see `triggers/examples/` for inspiration)

3. **Trigger state** — check `~/.xgh/triggers/.state.json`:
   - List any triggers currently silenced (silenced_until in the future)
   - Report triggers that fired in the last 24h
   - ⚠️ if any trigger has `fire_count > 10` with backoff — may be stuck in backoff loop

4. **Hook registration** — check if PostToolUse hook is active:
   - Run `claude config list` and check for post-tool-use hook
   - ✅ PostToolUse hook registered (local command triggers will work)
   - ⚠️ PostToolUse hook not found — `source: local` triggers won't fire automatically.
     Run `/xgh-setup` to configure.

5. **Example output:**
   ```
   Check 8: Trigger engine
   ✅ Global config: enabled=true | action_level=create | fast_path=true
   ✅ 4 triggers (3 enabled, 1 disabled)
   ⚠️ pr-stale-reminder: silenced until 2026-03-22T09:00:00Z
   ✅ Fired last 24h: p0-alert (2 times)
   ⚠️ PostToolUse hook not registered — source:local triggers inactive
   ```
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep "doctor"
```

Expected: doctor assertions pass.

- [ ] **Step 4: Commit**

```bash
git add skills/doctor/doctor.md
git commit -m "feat(trigger): add trigger health check to doctor skill"
```

---

## Task 8: Trigger suggestions in track skill

**Files:**
- Modify: `skills/track/track.md`

After generating a provider's YAML and fetch.sh, the agent suggests relevant triggers and writes selected ones to `~/.xgh/triggers/`.

- [ ] **Step 1: Find where provider generation completes in track.md**

```bash
grep -n "persist\|user_providers\|regenerate\|lossless\|store" skills/track/track.md | tail -15
```

Locate the final step that stores completion (lcm_store) or the Regeneration section.

- [ ] **Step 2: Insert trigger suggestion step before the lossless-claude store call**

Find the `lcm_store` call at the end of `skills/track/track.md` and insert this block before it:

```markdown
## Step: Suggest triggers

After generating the provider, suggest relevant triggers based on provider type and roles.

1. Determine provider type from the generated `provider.yaml` (roles: list, alerts, prs, etc.)
2. Present 3-5 relevant trigger suggestions. Examples by role:

   **GitHub (PRs, issues, actions):**
   1. PR awaiting review >24h → DM you
   2. CI failure on main branch → notify #engineering
   3. Security alert (critical) → DM you + create GitHub issue
   4. New release on watched repo → create upgrade issue

   **Jira (list, comments):**
   1. P0/blocker issue created → notify #incidents
   2. Ticket assigned to you → DM you
   3. Sprint blocked → alert channel

   **Slack (channels, threads):**
   1. Direct mention in monitored channel → DM you with context
   2. Message matches crisis keywords → notify #incidents

   **Sentry (alerts):**
   1. Error spike (>100 in 5min) → notify #engineering
   2. New issue (critical) → create Jira ticket

   **Local (npm, cargo, gh release):**
   1. `npm publish` success → tag GitHub release + notify Slack

   **Schedule:**
   1. Monday 9am → run /xgh-brief and post summary

3. Ask: "Enable any? [1,2,3 / all / none]"
4. For each selected trigger:
   - Generate a YAML file in `~/.xgh/triggers/<provider>-<trigger-slug>.yaml`
   - Use `schema_version: 1`, `enabled: true`, appropriate `backoff: exponential`
   - Set `path: fast` only for critical/P0 triggers; `path: standard` for everything else
   - Use conservative `action_level: notify` by default; prompt to elevate if user wants create/autonomous
   - Write the file using `Write` tool
5. Confirm: "✅ Created N triggers in ~/.xgh/triggers/"
   Show the paths of created files.
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep "track"
```

Expected: track assertion passes.

- [ ] **Step 4: Commit**

```bash
git add skills/track/track.md
git commit -m "feat(trigger): add trigger suggestion step to /xgh-track"
```

---

## Task 9: Schedule-event trigger evaluation in schedule skill

**Files:**
- Modify: `skills/schedule/schedule.md`

Schedule-based triggers fire on cron expressions. The scheduler already runs `/xgh-retrieve` and `/xgh-analyze` on intervals. This adds a dedicated pass for `source: schedule` triggers.

- [ ] **Step 1: Find the main flow section in schedule.md**

```bash
grep -n "Step\|retrieve\|analyze\|cron\|CronCreate" skills/schedule/schedule.md | head -30
```

Locate where the scheduler sets up jobs, or where it describes the scheduled runs.

- [ ] **Step 2: Add schedule-event trigger evaluation section**

Find the last Step or the final section in `skills/schedule/schedule.md` (before output discipline) and append:

```markdown
## Schedule-event trigger evaluation

During each scheduled retrieve/analyze cycle, evaluate `source: schedule` triggers.

1. Read `~/.xgh/triggers.yaml` — if `enabled: false`, skip entirely.
2. Read all `~/.xgh/triggers/*.yaml` where `when.source: schedule`.
3. For each schedule trigger:
   a. Parse the `cron:` expression (standard 5-field: min hour dom mon dow).
   b. Check if the expression matches the current time (within the run window).
      A cron matches if it would have fired in the last `retrieve_interval` minutes.
   c. Check cooldown/backoff (same logic as standard path — see xgh:trigger skill).
   d. If matched and cooldown clear: execute `then:` steps.
   e. Update `.state.json`.
4. Log: `Schedule triggers: N evaluated, K fired`

**Cron evaluation note:** Use a simple check — compare cron fields against current
`date` output. For `0 9 * * MON`: fire if current hour=9, minute<5, weekday=Monday.
Exact match within the retrieve window (5min) is sufficient; cron-exact precision
is not required for this use case.
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep "schedule"
```

Expected: schedule assertions pass.

- [ ] **Step 4: Commit**

```bash
git add skills/schedule/schedule.md
git commit -m "feat(trigger): add schedule-event trigger evaluation to schedule skill"
```

---

## Task 10: Example trigger files

**Files:**
- Create: `triggers/examples/README.md`
- Create: `triggers/examples/p0-alert.yaml`
- Create: `triggers/examples/pr-stale-reminder.yaml`
- Create: `triggers/examples/npm-post-publish.yaml`
- Create: `triggers/examples/weekly-standup.yaml`

These are templates users copy to `~/.xgh/triggers/` and customize. Include generous comments.

- [ ] **Step 1: Create the directory**

```bash
mkdir -p triggers/examples
```

- [ ] **Step 2: Create triggers/examples/README.md**

```markdown
# Trigger Examples

Copy any of these to `~/.xgh/triggers/` to activate them. Edit to your needs.

**DO NOT** edit files here directly — they're reset on plugin updates.

## Getting started

```bash
cp triggers/examples/p0-alert.yaml ~/.xgh/triggers/p0-alert.yaml
# edit ~/.xgh/triggers/p0-alert.yaml with your Slack channel
```

Then run `/xgh-trigger list` to see it. Run `/xgh-trigger test p0-alert` to dry-run it.

## Examples

| File | Event | Action | Level |
|------|-------|--------|-------|
| p0-alert.yaml | P0 issue in Jira | Slack #incidents + investigate | autonomous |
| pr-stale-reminder.yaml | PR awaiting review >24h | DM you | notify |
| npm-post-publish.yaml | `npm publish` succeeds | Tag release + Slack | create |
| weekly-standup.yaml | Monday 9am | Run /xgh-brief, post to Slack | notify |

## Global config

Before triggers fire, set your global cap in `~/.xgh/triggers.yaml`:

```yaml
enabled: true
action_level: notify   # start here; elevate to create/autonomous when ready
fast_path: true
cooldown: 5m
```
```

- [ ] **Step 3: Create triggers/examples/p0-alert.yaml**

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# P0 Alert Trigger
# ─────────────────────────────────────────────────────────────────────────────
# Fires when a P0 or blocker issue lands in your inbox from Jira.
# Notifies #incidents immediately. If score >= 90, dispatches /xgh-investigate.
#
# Requires: action_level: autonomous in ~/.xgh/triggers.yaml (for dispatch step)
# Copy to: ~/.xgh/triggers/p0-alert.yaml
# ─────────────────────────────────────────────────────────────────────────────

schema_version: 1
name: P0 alert
description: Alert on critical Jira P0/blocker issues and auto-investigate if urgent
enabled: true

when:
  source: jira               # fires on Jira inbox items
  type: p0                   # content type from analyze classification
  project: "*"               # any project (* = wildcard)
  match:
    title: "blocker|critical|P0|sev1"   # case-insensitive keyword match
    author: "!bot-*"                    # exclude bot authors (! = exclude)

# Fast path: fire during retrieve (5-min window) based on urgency score alone.
# type: won't match on fast path — use urgency_score + match keywords instead.
path: fast

# ── Firing policy ──────────────────────────────────────────────────────────
cooldown: 5m                 # minimum gap between firings
backoff: exponential         # 5m → 10m → 20m → 40m ... (caps at max_cooldown)
max_cooldown: 6h             # never wait longer than 6h between re-alerts
reset_after: 2h              # if quiet for 2h, reset backoff to base cooldown

# ── Actions ────────────────────────────────────────────────────────────────
# Trigger-level cap. Steps cannot exceed this. Cannot exceed global cap.
action_level: autonomous

then:
  # Step 1: Alert the team immediately [level: notify]
  - notify: slack
    channel: "#incidents"
    message: |
      🚨 *P0 Alert*: {item.title}
      Project: {item.project} | Score: {item.urgency_score}
      Ticket: {item.url}
    on_error: continue        # keep going if Slack is down

  # Step 2: DM yourself [level: notify]
  - notify: dm
    message: "P0 needs your attention: {item.title} ({item.url})"
    on_error: continue

  # Step 3: Auto-investigate if critically urgent [level: autonomous]
  # Only fires if global action_level >= autonomous
  - if: item.urgency_score >= 90
    dispatch: /xgh-investigate
    args: "{item.url}"
    on_complete:
      - notify: slack
        channel: "#incidents"
        message: |
          🔍 Investigation complete for {item.title}:
          {result.summary}
    on_error: abort           # don't notify on broken investigation
```

- [ ] **Step 4: Create triggers/examples/pr-stale-reminder.yaml**

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# PR Stale Reminder Trigger
# ─────────────────────────────────────────────────────────────────────────────
# Fires when a PR has been awaiting review for >24h.
# Sends a DM to remind you to review or follow up.
#
# Requires: action_level: notify (default)
# Copy to: ~/.xgh/triggers/pr-stale-reminder.yaml
# ─────────────────────────────────────────────────────────────────────────────

schema_version: 1
name: PR stale reminder
description: DM when a PR is awaiting review for more than 24h
enabled: true

when:
  source: github             # fires on GitHub inbox items
  type: awaiting_their_reply # PR waiting on reviewer — from analyze classification
  project: "*"               # any project
  match:
    title: "review|PR|pull request"   # keyword filter (case-insensitive)

path: standard               # no rush — evaluate during 30-min analyze cycle

# ── Firing policy ──────────────────────────────────────────────────────────
cooldown: 4h                 # remind at most every 4h per PR
backoff: exponential         # back off if ignored: 4h → 8h → 16h → 24h
max_cooldown: 24h            # remind at least once a day
reset_after: 12h             # reset if PR gets activity

action_level: notify

then:
  # DM yourself with the PR details
  - notify: dm
    message: |
      👀 PR needs review: *{item.title}*
      Repo: {item.repo} | PR #{item.number}
      Link: {item.url}
      Waiting: {item.urgency_score} urgency
    on_error: continue
```

- [ ] **Step 5: Create triggers/examples/npm-post-publish.yaml**

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# npm Post-Publish Lifecycle Trigger
# ─────────────────────────────────────────────────────────────────────────────
# Fires after a successful `npm publish`. Tags a GitHub release and
# notifies your team on Slack.
#
# Requires:
#   - action_level: create in ~/.xgh/triggers.yaml (for gh release create)
#   - PostToolUse hook active (run /xgh-setup to configure)
#   - GITHUB_REPO env var set, or edit the run: block below
#
# Copy to: ~/.xgh/triggers/npm-post-publish.yaml
# ─────────────────────────────────────────────────────────────────────────────

schema_version: 1
name: npm post-publish
description: After npm publish — tag GitHub release, notify Slack
enabled: true

when:
  source: local              # fires on local bash command events
  command: "npm publish"     # regex matched against the Bash command
  exit_code: 0              # only on success

path: standard

# ── Firing policy ──────────────────────────────────────────────────────────
cooldown: 1m                 # typically one publish per session
backoff: none                # don't back off — every publish should fire
max_cooldown: 5m

action_level: create

then:
  # Step 1: Read version and tag GitHub release [level: create]
  # All $ITEM_* env vars are available. Add your own repo in GITHUB_REPO.
  - name: Tag GitHub release
    shell: bash
    run: |
      VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "unknown")
      PKG_NAME=$(node -p "require('./package.json').name" 2>/dev/null || echo "package")
      REPO="${GITHUB_REPO:-}"
      if [ -n "$REPO" ]; then
        gh release create "v$VERSION" \
          --repo "$REPO" \
          --title "$PKG_NAME v$VERSION" \
          --generate-notes
        echo "Tagged: v$VERSION for $REPO"
      else
        echo "Skipped: GITHUB_REPO not set"
      fi
    on_error: continue

  # Step 2: Notify Slack [level: notify]
  - notify: slack
    channel: "#releases"
    message: |
      📦 Published! {item.title}
      Run: `npm install <package>@latest`
    on_error: continue

  # Step 3: DM yourself [level: notify]
  - notify: dm
    message: "✅ npm publish succeeded: {item.title}"
    on_error: continue
```

- [ ] **Step 6: Create triggers/examples/weekly-standup.yaml**

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# Weekly Standup Briefing Trigger
# ─────────────────────────────────────────────────────────────────────────────
# Every Monday at 9am, runs /xgh-brief and posts the summary to Slack.
# Turns xgh into a proactive reporter, not just a reactive assistant.
#
# Requires: action_level: notify (default)
# Optional: Slack integration (remove the notify step if you don't use Slack)
# Copy to: ~/.xgh/triggers/weekly-standup.yaml
# ─────────────────────────────────────────────────────────────────────────────

schema_version: 1
name: Weekly standup briefing
description: Every Monday 9am — run /xgh-brief and post summary to Slack
enabled: true

when:
  source: schedule
  cron: "0 9 * * MON"       # Every Monday at 9:00am (local timezone)

path: standard               # evaluated during scheduled analyze run

# ── Firing policy ──────────────────────────────────────────────────────────
cooldown: 6h                 # don't re-fire same morning if analyze runs twice
backoff: none                # same time every week — no backoff needed
max_cooldown: 6h

# dispatch: requires action_level: autonomous globally in ~/.xgh/triggers.yaml
# For notify-only, remove the dispatch step and uncomment the DM-only alternative below
action_level: autonomous

then:
  # Step 1: Run /xgh-brief and capture summary [level: autonomous]
  # Requires: action_level: autonomous in ~/.xgh/triggers.yaml
  - dispatch: /xgh-brief
    on_complete:
      # Post brief to your team channel
      - notify: slack
        channel: "#team-updates"
        message: |
          🐴 *Weekly Brief — {item.timestamp}*
          {result.summary}
      # DM yourself the full brief
      - notify: dm
        message: "Your Monday brief is ready: {result.summary}"
    on_error: continue

  # Alternative (if action_level: autonomous not enabled — set action_level: notify above):
  # Remove the dispatch block above and uncomment this instead.
  # - notify: dm
  #   message: "Monday morning — time to run /xgh-brief!"
```

- [ ] **Step 7: Run tests**

```bash
bash tests/test-trigger.sh 2>&1 | grep -E "example|trigger"
```

Expected: all example file assertions pass.

- [ ] **Step 8: Run full test suite**

```bash
bash tests/test-trigger.sh
```

Expected: all assertions pass.

- [ ] **Step 9: Run config tests to catch regressions**

```bash
bash tests/test-config.sh
```

Expected: PASS. If new failures: investigate before committing.

- [ ] **Step 10: Commit**

```bash
git add triggers/examples/
git commit -m "feat(trigger): add example trigger YAMLs with inline documentation"
```

---

## Final: full test pass + push

- [ ] **Step 1: Run the full test suite**

```bash
bash tests/test-config.sh && bash tests/test-trigger.sh
```

Expected: all assertions pass.

- [ ] **Step 2: Push**

```bash
git push
```
