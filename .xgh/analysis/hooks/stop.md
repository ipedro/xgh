---
hook: Stop
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# Stop Hook — Analysis for xgh

## 1. Hook Spec

The Stop hook fires whenever Claude finishes generating a response and hands control back to the user. Crucially, "stop" in Claude Code's lifecycle covers more events than just a clean end-of-turn:

- Normal turn completion (Claude finished answering)
- `/clear` — context cleared, new session effectively begins
- `/compact` — context compressed, previous turns summarized
- Resume — a paused or backgrounded session resumes
- Tool-call completion — each tool call's result triggers a stop before Claude re-enters

**Input received:** A JSON payload that includes the current session state: session ID, the conversation transcript up to that point (or a summary if compacted), current working directory, and any active tool results. The hook cannot read future turns.

**Output it can return:**

- `systemMessage` — a string injected into the next system prompt Claude sees. This is the primary mechanism for passing state forward across the stop boundary.
- `decision` — a blocking signal (`block`) that halts the session. In practice, Stop hooks rarely block; they are primarily passive actors that write side-effects or inject context.

Stop hooks cannot prompt the user, open dialogs, or return user-visible output directly. Their influence is indirect: write to disk, write to the YAML, or inject a system message into the next turn.

---

## 2. Capabilities

### End-of-turn actions
The hook can run any shell command after Claude stops — git operations, file writes, API calls — without interfering with the conversation flow. The user sees nothing unless the hook injects a `systemMessage`.

### Persistence
This is the hook's strongest capability in the xgh context. Because `config/project.yaml` is the declared preference registry, a Stop hook can write discovered values back to it using the same `cache_pr_pref` pattern already in `lib/config-reader.sh`. A preference surfaced during a session (e.g., user corrects a merge method) becomes durable across sessions.

### Cleanup
Temporary files, lock files, in-progress scratch pads, or `.xgh/session/` working state can be flushed at stop time without requiring the user to remember a teardown command.

### Summary injection
By writing a `systemMessage`, the hook can seed the next turn's system prompt with a compact summary of what happened: files changed, PRs opened, decisions made. This survives `/compact` and `/clear` because it's injected fresh at each stop, not stored in the conversation history.

---

## 3. Opportunities for xgh

### Preference persistence (config drift capture)
During a session Claude may override a default — a different reviewer, a different merge method, a branch-specific squash preference. Currently those overrides live only in the turn. A Stop hook can detect overrides applied this session and write them back to `config/project.yaml` under `preferences.pr.branches.<branch>` using the `cache_pr_pref` logic already in `lib/config-reader.sh`. This closes the loop between "what the user actually did" and "what the YAML declares."

### Session audit trail
The hook can append a structured entry to `.xgh/session-log.jsonl` at each stop: timestamp, session ID, CWD, a one-line summary of the last turn's action (extracted from the transcript). Over time this becomes the raw material for `/xgh-briefing`'s "IN PROGRESS" section — the briefing skill can query the log for recent sessions instead of relying on git log alone.

### Config drift detection
At stop time, the hook can compare the current `config/project.yaml` against what `probe_pr_field` would return for the same values — i.e., what GitHub/Copilot actually reports today. If they diverge, the hook can inject a `systemMessage` warning: "project.yaml declares `merge_method: squash` but the repo's branch protection currently requires `merge`. Consider running `/xgh-release` to reconcile." This is the Terraform analogy applied directly: declared state vs. actual state, surfaced automatically.

---

## 4. Pitfalls

### Fires on every stop, including non-user-initiated ones
`/compact`, `/clear`, and resume all trigger Stop. A hook that writes to disk on every stop will write on compaction, which happens automatically in long sessions. Guard against this with a session-state flag (e.g., a temp file under `/tmp/xgh-<session-id>/`) that distinguishes a productive stop from a lifecycle stop.

### Must be fast
Stop hooks run synchronously before Claude re-enters. A slow hook (e.g., a network call to the GitHub API) adds latency to every turn. Keep Stop hook logic to local file I/O and lightweight shell operations. Defer anything heavier to a background process or to the next PreToolUse cycle.

### Cannot prompt the user
The hook has no stdout channel to the conversation. Any advisory output must go through `systemMessage` injection, which means it appears at the top of the next system prompt — useful but invisible unless Claude explicitly surfaces it.

### Unreliable for critical writes
Because Stop fires on `/clear` and `/compact`, a hook that assumes it only fires at "end of meaningful work" will fire at unexpected times. Never use Stop as the sole mechanism for writing critical state. Treat it as a best-effort persistence layer; treat `config/project.yaml` as the authoritative source, not the hook's output.

---

## 5. Concrete Implementations

### Implementation A — Preference Write-Back Hook

A Stop hook script at `.claude/hooks/stop/write-back-prefs.sh` that:

1. Reads `/tmp/xgh-<session-id>/overrides.json` — a file that PreToolUse or UserPromptSubmit hooks write to whenever a skill applies a non-default preference.
2. For each entry, calls `cache_pr_pref` (sourcing `lib/config-reader.sh`) to write it to `config/project.yaml`.
3. If any writes occurred, injects a `systemMessage`: "Persisted N preference overrides to config/project.yaml this session."

This makes xgh's config system self-healing: the YAML converges toward what the user actually does, not just what they initially declared.

### Implementation B — Session Log Entry

A Stop hook that appends to `.xgh/session-log.jsonl`:

```json
{"ts": "2026-03-25T14:22:00Z", "session": "abc123", "cwd": "/Users/pedro/Developer/xgh", "branch": "fix/release-squash", "last_action": "opened PR #123 via /release skill"}
```

The `last_action` field is extracted from a lightweight parse of the final assistant turn (look for PR URLs, commit SHAs, skill invocations). The `/xgh-briefing` skill's "IN PROGRESS" section reads this log to reconstruct where work left off — more reliable than git log because it captures Claude-mediated actions that don't always produce commits.

### Implementation C — Drift Detection + systemMessage Warning

A Stop hook that runs a fast diff between `config/project.yaml`'s declared `merge_method` and the current branch protection setting (cached locally in `.xgh/cache/repo-settings.json`, refreshed by a separate PreToolUse hook). If they diverge, the hook returns:

```json
{
  "systemMessage": "⚠ Config drift detected: project.yaml declares merge_method=squash but main branch protection requires merge. Remind the user to reconcile with /release or update project.yaml."
}
```

This surfaces the Terraform-style "plan shows drift" pattern inside the Claude conversation without any user action required — exactly xgh's declared mission applied to its own config system.

---

## Summary

The Stop hook is xgh's best candidate for **passive convergence** — the mechanism by which declared state (project.yaml) and actual state (what happened this session) stay in sync without requiring the user to remember a save step. Its main constraints are latency sensitivity and the need to guard against lifecycle-triggered stops. Used correctly, it is the final piece of the declare → converge → audit loop that defines xgh's core value proposition.
