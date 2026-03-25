---
hook: PreCompact
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# PreCompact Hook — Analysis for xgh

## 1. Hook Spec

**When it fires**: Immediately before Claude Code performs context compaction — either triggered manually by the user (`/compact`) or automatically when the context window approaches its limit. The hook matcher is `"manual"` or `"auto"` depending on the trigger source.

**Input received**: The hook receives a JSON payload on stdin containing:
- `trigger` — `"manual"` | `"auto"`
- `session_id` — the current Claude Code session ID
- `context_token_count` — approximate token count before compaction
- The full conversation transcript is NOT passed; the hook operates on metadata, not raw messages

**Output it can return**: The hook returns JSON to stdout. The recognized fields are:
- `summary` — a string Claude Code prepends to the post-compaction context as a "memory anchor." This is the primary lever: whatever this hook emits here survives compaction.
- Returning a non-zero exit code blocks compaction (use sparingly — only when data must be flushed first).

**Execution environment**: The hook script runs in the repo root, with `$CLAUDE_PROJECT_DIR`, `$HOME`, and the git context available. It has no network sandbox restrictions — it can write files, call `lcm_store`, update the context tree.

---

## 2. Capabilities

PreCompact is the **last-write window** before the conversation history is summarized away. Concretely, it can:

- **Write to persistent stores** before they're unreachable: lossless-claude (`lcm_store`), context tree files under `.xgh/context-tree/`, or `~/.xgh/` user config.
- **Inject a structured summary** into the compaction anchor — shaping what the post-compaction Claude "remembers" about the session.
- **Detect compaction pressure** via `trigger=auto` and behave more aggressively (e.g., flush a longer summary) than for a manual `/compact`.
- **Record session statistics**: token counts, tools used, decisions made, skills invoked — data that would otherwise evaporate.

What it cannot do: read the full transcript. The hook cannot re-scan every message. It works with what has already been written to disk by prior hooks (PostToolUse, session-start) and the structured metadata in the payload.

---

## 3. Opportunities for xgh

### 3a. Preference signal extraction — closing the config loop

During a session, the user implicitly reveals preferences: they override a merge method, correct a reviewer slug, change a model choice. These corrections live in conversation turns that compaction will compress to a one-line summary. PreCompact is the right moment to flush any such runtime overrides back to `config/project.yaml` — or at minimum to a pending-preferences queue that `/xgh-sync-prefs` can review.

This directly extends the `load_pr_pref` resolution order (CLI flag > branch override > project default > probe). A PreCompact hook could promote CLI-flag values used during the session to "project default" candidates, narrowing the gap between what the user actually wants and what the YAML says.

### 3b. Context tree auto-curation

The context tree (`$.xgh/context-tree/`) is the human-readable knowledge base xgh commits to git. Significant decisions made mid-session — architecture choices, rationale for deviating from a plan, new gotchas discovered — belong there. But the agent writing them is usually deep in task execution and doesn't always invoke `/xgh-store` at the right moment.

PreCompact can act as a **safety net**: scan the PostToolUse log written by `hooks/post-tool-use.sh` for tool calls that signal a meaningful decision (e.g., Edit calls touching `lib/`, `config/`, `providers/`), and emit a `summary` that includes structured bullets for the context-curator agent to ingest on the next session start.

### 3c. Session handoff packet — reducing next-session ramp-up

xgh's `/xgh-brief` skill searches lossless-claude and the context tree at session start to reconstruct "what were we doing?" A PreCompact hook that writes a `~/.xgh/last-session.md` handoff file (branch, open tasks, last decision, next action) gives `/xgh-brief` a deterministic fast path instead of a BM25 search over sparse context-tree entries.

---

## 4. Pitfalls

**Timing pressure**: The `auto` trigger fires when context is already near the limit. The hook must complete in under ~2 seconds or Claude Code will time out and compact without the summary. No subprocess chains, no `gh api` calls, no Python startup overhead unless cached.

**Hook failure is silent compaction**: If the hook exits non-zero, Claude Code may still compact (behavior depends on Claude Code version). Data not written before exit is lost. Write first, exit second — never accumulate state in memory waiting for a "done" signal.

**No transcript access = no replay**: The hook cannot reconstruct decisions from conversation text. It can only act on what prior hooks (PostToolUse) already persisted to disk. If `hooks/post-tool-use.sh` didn't log a tool call, PreCompact has no way to recover it.

**Config mutation risk**: If PreCompact auto-promotes a runtime override to `config/project.yaml`, it creates an uncommitted file change. The next git operation will pick it up, possibly surprising the user. Any YAML mutation must be gated behind an explicit flag (e.g., `XGH_PRECOMPACT_WRITE_PREFS=1`) and clearly logged.

**Idempotency**: `auto` compaction can be triggered multiple times in a long session. The hook must be idempotent — writing the same session state twice must not corrupt `~/.xgh/last-session.md` or lossless-claude with duplicate entries.

---

## 5. Concrete Implementations

### Example A — Pending-prefs flush

```bash
# hooks/pre-compact.sh
# If ~/.xgh/pending-prefs.json was written by session-start or post-tool-use,
# emit its contents as a summary bullet so the next session sees it.

PENDING="$HOME/.xgh/pending-prefs.json"
if [[ -f "$PENDING" ]]; then
  prefs=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('; '.join(f\"{k}={v}\" for k,v in d.items()))" "$PENDING" 2>/dev/null)
  echo "{\"summary\": \"PENDING PREF CHANGES from this session: $prefs — run /xgh-sync-prefs to promote to config/project.yaml\"}"
fi
```

This keeps the config-reader.sh resolution chain honest: nothing is auto-mutated, but the information survives compaction as a visible anchor the next session will see.

### Example B — Context-tree decision anchor

```bash
# Scan post-tool-use log for Edit calls on significant paths, emit summary
LOG="$HOME/.xgh/session-$(git rev-parse HEAD 2>/dev/null | head -c8).log"
if [[ -f "$LOG" ]]; then
  decisions=$(grep 'Edit:' "$LOG" | grep -E '(lib/|config/|providers/)' | tail -5 | sed 's/^/  - /')
  if [[ -n "$decisions" ]]; then
    echo "{\"summary\": \"FILES CHANGED THIS SESSION (context-tree candidates):\n$decisions\"}"
  fi
fi
```

The context-curator agent (haiku, `context-tree curation indexing` capabilities) can parse these anchors on next session start and generate proper context-tree entries without needing to re-read the full diff.

### Example C — Session handoff file

```bash
# Write ~/.xgh/last-session.md before compaction destroys branch/task state
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
LAST_COMMIT=$(git log -1 --oneline 2>/dev/null)
cat > "$HOME/.xgh/last-session.md" <<EOF
# Last Session Handoff
branch: $BRANCH
last_commit: $LAST_COMMIT
compacted_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
trigger: ${TRIGGER:-unknown}
EOF
echo "{\"summary\": \"Session state saved to ~/.xgh/last-session.md — /xgh-brief will load it on next start\"}"
```

This gives `/xgh-brief` a sub-100ms fast path: check for `~/.xgh/last-session.md` before running BM25 over the full context tree.

---

## Summary

PreCompact is xgh's **memory checkpoint gate** — the last reliable moment to move session knowledge from volatile context into durable storage. Its primary value for xgh is not blocking compaction but shaping the compaction anchor (`summary` output) and flushing to lossless-claude / context-tree / pending-prefs before the window closes. The hook must be fast (<2s), idempotent, and write-first. It completes the loop that `config/project.yaml` + `lib/config-reader.sh` open: preferences discovered at runtime can be flagged for promotion rather than silently lost.
