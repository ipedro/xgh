# Context-Mode Enforcement for xgh

**Date:** 2026-03-18
**Status:** Draft
**Problem:** Context-mode goes unused despite advisory hooks, wasting tokens and money.

## Background

Context-mode provides tools (`ctx_execute_file`, `ctx_batch_execute`, `ctx_execute`) that keep
raw output in a sandbox, returning only printed summaries to the context window. Even a single
call can save 40% of context. However, in practice, agents routinely bypass these tools:

- Read is used for analysis instead of `ctx_execute_file`
- Bash is used for multi-command research instead of `ctx_batch_execute`
- Context-mode's PreToolUse hook fires advisory "tips" that are easily rationalized away

Root causes:
1. **Advisory hooks lack teeth** — "tip" framing is optional-feeling
2. **Zero context-mode awareness in skills** — superpowers and xgh skills never mention how to read files efficiently
3. **No session-level feedback loop** — nothing notices "5 Reads, 0 ctx calls" and escalates

## Solution: Four-Layer Defense in Depth

Each layer strengthens the previous. Implementation order matches layer number.

### Layer 1: Foundation — Shared Reference Doc + Session-Start Priming

**New file:** `plugin/references/context-mode-routing.md`

Single source of truth for context-mode routing rules. Contains:

- **Routing table:**

| Action | Tool | When |
|--------|------|------|
| Understand / analyze a file | `ctx_execute_file(path)` | Always, unless Edit follows within 1-2 tool calls |
| Read a file to Edit it | `Read` | Only when the next action is Edit on the same file |
| Run multiple commands / searches | `ctx_batch_execute(commands, queries)` | Any multi-command research |
| Run builds, tests, log processing | `ctx_execute(language, code)` | Output expected >20 lines |
| Quick git/mkdir/rm | `Bash` | Output expected <20 lines |

- **The "next action test":** If your next action is NOT an Edit on the same file, use
  `ctx_execute_file`.
- **Phase-specific guidance:**
  - Investigation/debugging: `ctx_execute_file` for all file reads, `ctx_batch_execute` for
    searches. Switch to `Read` only in implementation phase when editing.
  - Implementation: `Read` for files about to be Edited. `ctx_execute` for builds/tests.
- **Examples of correct and incorrect patterns** (drawn from real session mistakes).

**Session-start change:** Add to the `decision_table` list in `plugin/hooks/session-start.sh`:
```python
"For file analysis: use ctx_execute_file, not Read. Read is only for files about to be Edited."
```

This primes every session before any skill loads or tool fires.

### Layer 2: Teaching — Skill Preambles

**Inline preamble template** (carried by every xgh skill, ~4 lines):

```markdown
> **Context-mode:** Use `ctx_execute_file` for analysis reads; `Read` only for files you will
> Edit within 1-2 tool calls. Use `ctx_batch_execute` for multi-command research. Full routing
> rules: `plugin/references/context-mode-routing.md`
```

**Scope:** All xgh skills. The preamble is brief enough to not add noise to light skills
(doctor, schedule) while providing essential routing guidance to heavy skills (investigate,
implement, deep-retrieve).

**Heavy skills** (investigate, implement, deep-retrieve, retrieve, analyze) additionally
reference the full doc for phase-specific guidance in their own context-mode section.

**Skills to update:**
- `plugin/skills/investigate/investigate.md`
- `plugin/skills/implement/implement.md`
- `plugin/skills/deep-retrieve/deep-retrieve.md`
- `plugin/skills/retrieve/retrieve.md`
- `plugin/skills/analyze/analyze.md`
- `plugin/skills/briefing/briefing.md`
- `plugin/skills/doctor/doctor.md`
- `plugin/skills/init/init.md`
- `plugin/skills/track/track.md`
- `plugin/skills/index/index.md`
- `plugin/skills/profile/profile.md`
- `plugin/skills/schedule/schedule.md`
- `plugin/skills/calibrate/calibrate.md`
- `plugin/skills/collab/collab.md`
- `plugin/skills/design/design.md`
- `plugin/skills/ask/ask.md`
- `plugin/skills/curate/curate.md`
- `plugin/skills/command-center/command-center.md`
- `plugin/skills/deep-retrieve/deep-retrieve.md`

### Layer 3: Enforcement — PreToolUse Hook with Escalating Warnings

**State file:** `/tmp/xgh-ctx-health-{hash}.json`

Where `{hash}` is derived from the worktree root:
```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HASH="$(echo "$PROJECT_ROOT" | shasum | cut -c1-8)"
STATE_FILE="/tmp/xgh-ctx-health-${HASH}.json"
```

This is worktree-safe — each worktree gets its own state file. `/tmp/` is cleaned up by the OS.

**State schema:**
```json
{
  "reads": 0,
  "edits": 0,
  "ctx_calls": 0,
  "files_read": []
}
```

**Session-start initialization:** The session-start hook resets the state file at the start of
every session. This prevents stale data from previous sessions.

```python
import hashlib, subprocess, json
project_root = subprocess.check_output(
    ["git", "rev-parse", "--show-toplevel"],
    stderr=subprocess.DEVNULL
).decode().strip()
hash_val = hashlib.sha1(project_root.encode()).hexdigest()[:8]
state_path = f"/tmp/xgh-ctx-health-{hash_val}.json"
json.dump({"reads": 0, "edits": 0, "ctx_calls": 0, "files_read": []}, open(state_path, "w"))
```

Emit the state path in the hook output so hooks can derive it consistently.

**New hook: `plugin/hooks/pre-read.sh`** (PreToolUse on Read)

On every Read call:
1. Compute state file path from worktree root hash
2. Read current state, increment `reads`, append file path to `files_read`
3. Compute `unedited_reads = reads - edits`
4. Emit `additionalContext` based on escalation tier:

| Unedited Reads | Level | Message |
|---|---|---|
| 0-2 | Tip | "Context-mode: use ctx_execute_file for analysis reads." |
| 3-4 | Recommendation | "You've read N files and edited M. Use ctx_execute_file for analysis. Unedited files: [list]" |
| 5+ | Strong warning | "N reads, M edits, 0 ctx calls. You are wasting context. Switch to ctx_execute_file NOW. See plugin/references/context-mode-routing.md" |

5. Write updated state back to file

**New hook: `plugin/hooks/post-edit.sh`** (PostToolUse on Edit)

On every Edit call:
1. Increment `edits` in state file
2. Remove the edited file from `files_read` list (validates the preceding Read)

**New hook: `plugin/hooks/post-ctx-call.sh`** (PostToolUse on ctx_execute, ctx_execute_file,
ctx_batch_execute)

On every context-mode tool call:
1. Increment `ctx_calls` in state file

### Layer 4: Feedback Loop — Session Health Nudge

**Integration point:** Existing `plugin/hooks/prompt-submit.sh` (UserPromptSubmit hook).

On every user message, after existing intent detection logic:
1. Read state file
2. If `unedited_reads >= 3` AND `ctx_calls == 0`: append nudge to `additionalContext`
3. Nudge text: "Session health: {reads} reads, {edits} edits, 0 context-mode calls. Switch to
   ctx_execute_file for analysis reads."

**Design choices:**
- Fires per user message (low frequency, not noisy)
- Only triggers on a clear pattern (3+ unedited reads AND zero ctx calls)
- Appended to existing `additionalContext` output — no separate hook, single payload

## Hook Registration

The installer (`install.sh`) must register these hooks in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/xgh-pre-read.sh"}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/xgh-post-edit.sh"}]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/xgh-post-ctx-call.sh"}]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_execute_file",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/xgh-post-ctx-call.sh"}]
      },
      {
        "matcher": "mcp__plugin_context-mode_context-mode__ctx_batch_execute",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/xgh-post-ctx-call.sh"}]
      }
    ]
  }
}
```

Hooks are symlinked from `plugin/hooks/` to `~/.claude/hooks/` during install (existing pattern).

## File Inventory

| File | Action | Layer |
|------|--------|-------|
| `plugin/references/context-mode-routing.md` | Create | 1 |
| `plugin/hooks/session-start.sh` | Edit (add decision table entry + state init) | 1, 3 |
| All 19 skill files listed above | Edit (add 4-line preamble) | 2 |
| `plugin/hooks/pre-read.sh` | Create | 3 |
| `plugin/hooks/post-edit.sh` | Create | 3 |
| `plugin/hooks/post-ctx-call.sh` | Create | 3 |
| `plugin/hooks/prompt-submit.sh` | Edit (add nudge logic) | 4 |
| `install.sh` | Edit (register new hooks, add symlinks) | 3 |

## Testing

- **Layer 1:** Verify session-start output includes the new decision table entry
- **Layer 2:** Spot-check 3-4 skills for preamble presence
- **Layer 3:** Manual test: Read 3 files without editing, verify escalation messages appear.
  Edit a file, verify counter decrements. Use ctx_execute_file, verify ctx_calls increments.
- **Layer 4:** Manual test: accumulate 3+ unedited reads with 0 ctx calls, send a message,
  verify nudge appears in additionalContext.
- **Worktree isolation:** Run two sessions in different worktrees, verify independent state files.

## Risks

- **Hook performance:** Each Read/Edit adds a state file read/write. `/tmp/` is fast, JSON is
  small — negligible overhead.
- **Context-mode not installed:** Hooks reference context-mode tools. If context-mode is not
  installed, the PostToolUse matchers simply never fire (no ctx tools to match). The PreToolUse
  and nudge still work — they guide toward tools that won't be available, but the preamble
  mentions ctx_execute_file which would surface a helpful "tool not found" if context-mode is
  missing. Consider adding a guard in session-start that checks for context-mode availability.
- **Hook conflicts:** The installer already uses deep-merge for hooks arrays. New hooks merge
  alongside context-mode's existing hooks without overwriting.
