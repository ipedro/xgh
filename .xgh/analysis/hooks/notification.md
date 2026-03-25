---
hook: Notification
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# Notification Hook Analysis

## 1. Hook Spec

**When it fires:** The Notification hook fires when Claude Code emits a system notification — typically when a long-running task completes or when the agent needs to surface information while the user is not actively watching the session. Common triggers include task completion, waiting states, tool call results that require user attention, and session-level events that cross a significance threshold.

**Input received:** The hook receives a JSON payload on stdin containing:
- `notification_type` — a string categorizing the event (e.g., `"task_complete"`, `"waiting_for_input"`, `"error"`, `"rate_limit"`)
- `message` — the human-readable notification text Claude would have displayed
- `session_id` — the current session identifier
- `timestamp` — ISO 8601 event timestamp

Example payload shape:
```json
{
  "notification_type": "task_complete",
  "message": "PR #42 merged successfully via squash",
  "session_id": "abc123",
  "timestamp": "2026-03-25T14:32:00Z"
}
```

**Output it can return:** The hook can:
- Exit 0 to allow the default notification to proceed
- Exit non-zero to suppress the default notification
- Write a modified notification message to stdout to replace the default (where supported)
- Perform side effects (log to file, call external APIs, send to messaging systems) before returning

---

## 2. Capabilities

**Respond to system events:** The hook creates an observation point for every user-facing event Claude generates. This is the only hook that fires on Claude's *outbound* intent rather than on tool calls or prompt submission — making it uniquely suited for cross-cutting concerns like audit logging, alerting, and session summaries.

**Trigger side effects:** Because the hook runs in a full shell environment with access to all xgh tooling, it can invoke any xgh skill or provider as a reaction to a notification. A `task_complete` notification can fan out to Slack, Telegram, or a GitHub comment without any changes to the skill that produced the result.

**Log notifications:** The hook is a natural insertion point for a persistent notification ledger — append each event to `~/.xgh/notifications.log` or into lossless-claude's SQLite store for later BM25 query. This enables `xgh-track` to surface a timeline of what happened across sessions.

---

## 3. Opportunities for xgh

### Config-aware notification routing

`config/project.yaml` already carries the `preferences.pr.reviewer`, `preferences.dispatch.default_agent`, and provider keys. The Notification hook can read these via `xgh_config_get` from `lib/config-reader.sh` to decide *where* a notification goes:

```bash
provider=$(xgh_config_get "preferences.pr.provider" "github")
reviewer=$(xgh_config_get "preferences.pr.reviewer" "")
```

A `pr_merged` notification for a `github` project routes differently than one for a `gitlab` project. This keeps routing logic out of every individual skill and centralizes it in one hook file — the same philosophy as `load_pr_pref`.

### Integration with the xgh trigger/alerting system

The Automation Map in `AGENTS.md` defines triggers like `pr-opened`, `security-alert`, and `digest-ready`. The Notification hook can act as a *synthetic trigger emitter*: when Claude signals a `task_complete` notification for a PR merge, the hook can write a trigger event to a queue file that `pr-poller` or `collaboration-dispatcher` can consume. This closes the feedback loop between Claude's internal events and xgh's multi-agent bus without polling.

### Notification suppression based on pair_programming config

`preferences.pair_programming.enabled` and `preferences.pair_programming.phases` describe when xgh is actively pairing with the user. When `pair_programming.enabled: true` and the current phase is `per_task`, many intermediate notifications are redundant — the user is watching. The hook can read this flag and suppress low-signal notifications (e.g., `"searching files..."` progress pings) while preserving high-signal ones (`error`, `rate_limit`, `task_complete`). This reduces noise without losing anything important.

---

## 4. Pitfalls

**Limited documentation on notification types:** The set of values for `notification_type` is not formally documented in Claude Code's public spec. The hook must guard against unknown types gracefully (default-allow, log-and-continue) rather than fail closed and suppress legitimate alerts.

**Fires infrequently and unpredictably:** Unlike `post-tool-use` (which fires on every tool call) or `prompt-submit` (which fires on every turn), notifications are sparse and session-dependent. A hook that depends on notifications for critical state transitions will have large gaps. Use it for observability and side effects, not for control flow.

**Hard to test:** Because notifications are emitted by Claude's internal scheduler rather than deterministic user actions, triggering them in a test harness requires mocking the Claude runtime or injecting synthetic payloads directly into the hook script. The existing xgh `assert_*` bash test pattern works for unit-testing the hook's logic given a crafted stdin fixture, but end-to-end testing requires a live session.

**Risk of double-delivery:** If the hook sends a notification to an external system (Telegram, Slack) and then exits 0, the default Claude notification also fires. Unless the hook exits non-zero to suppress the default, users will receive duplicates. This must be an explicit design decision per notification type.

---

## 5. Concrete Examples

### Example A — Telegram relay for task_complete

When a long-running skill (e.g., `/release`, `/implement`) finishes, the user may not be watching the terminal. A Notification hook reads `preferences.pr.provider` and, for GitHub projects, posts to Telegram via the telegram MCP provider:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(git rev-parse --show-toplevel)/lib/config-reader.sh"

payload=$(cat)
type=$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('notification_type',''))")
msg=$(echo "$payload"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))")

if [[ "$type" == "task_complete" ]]; then
  # fire-and-forget; hook still exits 0 so default notification also shows
  xgh_notify_telegram "$msg" &
fi
```

### Example B — Notification ledger for xgh-track

Every notification is appended to a structured log consumed by `xgh-track`:

```bash
echo "$payload" | python3 -c "
import sys, json, datetime
d = json.load(sys.stdin)
d['logged_at'] = datetime.datetime.utcnow().isoformat()
with open(os.path.expanduser('~/.xgh/notifications.log'), 'a') as f:
    f.write(json.dumps(d) + '\n')
"
```

This gives `xgh-track` a queryable event history — supporting future `xgh-track notifications` commands that surface session timelines without requiring persistent background processes.

### Example C — Suppress verbose notifications during pair programming

```bash
source "$(git rev-parse --show-toplevel)/lib/config-reader.sh"

pair_enabled=$(xgh_config_get "preferences.pair_programming.enabled" "false")
type=$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('notification_type',''))")

LOW_SIGNAL_TYPES=("progress" "searching" "reading_file")

if [[ "$pair_enabled" == "true" ]]; then
  for low in "${LOW_SIGNAL_TYPES[@]}"; do
    if [[ "$type" == "$low" ]]; then
      exit 1  # suppress; user is watching
    fi
  done
fi
```

This respects the `pair_programming` preference block already in `project.yaml` without requiring any skill changes — a clean separation of concerns that fits xgh's declarative philosophy.
