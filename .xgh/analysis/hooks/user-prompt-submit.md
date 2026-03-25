---
hook: UserPromptSubmit
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# UserPromptSubmit Hook — Analysis for xgh

## 1. Hook Spec

**When it fires:** Immediately after the user submits a message, before Claude processes it. Every user turn — no exceptions.

**Input received:**

```json
{
  "session_id": "...",
  "transcript_path": "...",
  "hook_event_name": "UserPromptSubmit",
  "prompt": "the raw text the user typed"
}
```

The hook receives the full verbatim prompt text via stdin as JSON.

**Output it can return (via stdout JSON):**

| Field | Type | Effect |
|---|---|---|
| `action` | `"block"` or omit | Block stops Claude from processing the prompt; omitting allows it through |
| `reason` | string | When blocking, shown to the user as the rejection message |
| `additionalContext` | string | Injected as system-level context prepended to Claude's view of the prompt (invisible to user) |
| `hookSpecificOutput.updatedInput` | string | Fully replaces the prompt text Claude sees |

Exit code 0 = allow. Non-zero exit = Claude Code treats it as a blocking error.

---

## 2. Capabilities

**Intercept and gate user messages.** The hook can halt a prompt entirely — for example, blocking a destructive command pattern before Claude acts on it.

**Enrich prompts with context.** `additionalContext` is the primary power: inject project state, current preferences, branch context, or relevant memory excerpts without the user having to type them. Claude sees them; the user does not.

**Rewrite the prompt.** `updatedInput` allows full substitution — expand abbreviations, normalize shorthand, prepend or append boilerplate.

**Route and classify commands.** The hook sees the raw text before Claude's intent parsing, making it the earliest possible interception point for slash-command-style dispatch.

**Validate input.** Structural validation (e.g., "you must specify a target branch with /release") can produce a `block` response with a helpful `reason` rather than letting Claude guess.

---

## 3. Opportunities for xgh

### 3.1 Preference Intent Detection

When the user says something like "always use squash on main" or "set review model to opus," the hook can intercept the statement before Claude processes it and:

1. Detect preference-setting patterns via regex or keyword matching.
2. Write the new value to `config/project.yaml`.
3. Return `additionalContext` confirming the update: "I've written `pr.branches.main.merge_method: squash` to config/project.yaml."

This closes the loop between conversational intent and the declarative config system — exactly the "declare in conversation, converge the system" promise of xgh.

**Signal patterns to detect:**
- `(always|default to|set|use|change) .* (squash|merge|rebase)` (merge method)
- `(use|switch to|set) .* (opus|sonnet|haiku)` (model preferences)
- `(enable|disable) (auto.?merge|review.?on.?push|pair.?programming)`

### 3.2 Ambient Project Context Injection

On every prompt, inject a compact context block via `additionalContext` so Claude never operates blind:

```
[xgh context]
branch: fix/release-squash → target: develop
pr.merge_method: squash (develop), merge (main)
reviewer: copilot-pull-request-reviewer[bot]
auto_merge: true
```

This is analogous to what `config-reader.sh`'s `load_pr_pref` does at skill invocation time — except surfaced earlier, into the conversation layer. Claude can use it to answer questions like "what merge method should I use here?" without running a skill.

The hook reads from `config/project.yaml` via `xgh_config_get` (already implemented in `lib/config-reader.sh`) and formats a one-paragraph summary injected as hidden context.

### 3.3 Skill Shorthand Expansion

xgh skills are invoked as `/xgh-release`, `/xgh-dispatch`, etc. The hook can intercept common shorthand and rewrite:

| User types | Hook rewrites to |
|---|---|
| `/release patch` | `/xgh-release --bump patch` |
| `/pr` | `/xgh-pr --base develop` (reads default branch from project.yaml) |
| `ship it` | `/xgh-release --bump patch && /xgh-pr` |

This keeps the user-facing interface terse while the actual skill invocation is fully specified — no ambiguity for Claude to resolve.

---

## 4. Pitfalls

**Latency on every message.** This hook runs synchronously before every user turn. A hook that calls `yq` to parse YAML, runs a `git branch` check, and does regex matching must complete in tens of milliseconds, not seconds. Any I/O that blocks (network, slow disk) directly degrades perceived responsiveness. Keep the hook lean: precompute or cache what can be cached; use simple `grep`/`awk` over full YAML parsing where possible.

**False positives in intent detection.** Natural language is ambiguous. "I always use squash here" in the middle of explaining a concept should not silently rewrite `project.yaml`. Intent detection must be high-precision, not high-recall. Use conservative anchored patterns and, where ambiguous, prefer injecting `additionalContext` that asks Claude to confirm rather than writing the preference directly.

**Silent context injection creates debugging confusion.** When `additionalContext` is injected invisibly, Claude's behavior can seem inconsistent to users who don't know what the hook is adding. xgh should log injected context to `.xgh/hook-debug.log` (gated behind `XGH_DEBUG=1`) so the system is inspectable.

**Privacy exposure surface.** The hook receives every prompt — including passwords accidentally typed, private keys, sensitive questions. Any hook code that logs prompts, sends them to a remote endpoint, or stores them must be scrutinized carefully. xgh's hooks should be local-only and explicitly avoid persisting raw prompt text.

**Non-idempotent rewrites.** If `updatedInput` is used to expand shorthand, and Claude's response includes a re-statement of the user's message, the user may see the expanded form and be confused. Prefer `additionalContext` over `updatedInput` unless full replacement is clearly necessary.

---

## 5. Concrete Implementations

### Implementation A: Project Context Injector

A lightweight hook (`hooks/user-prompt-submit/inject-project-context.sh`) that runs on every prompt and calls `lib/config-reader.sh` to build a one-liner context block:

```bash
#!/usr/bin/env bash
# hooks/user-prompt-submit/inject-project-context.sh
set -euo pipefail
source "$(dirname "$0")/../../lib/config-reader.sh"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
MERGE_METHOD=$(load_pr_pref "merge_method" "" "$BRANCH")
MODEL=$(xgh_config_get "agents.default_model" "sonnet")
AUTO_MERGE=$(xgh_config_get "pr.auto_merge" "false")

CONTEXT="[xgh] branch=$BRANCH merge_method=$MERGE_METHOD default_model=$MODEL auto_merge=$AUTO_MERGE"

jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
```

Cost: one `git` call + two `yq` calls per prompt. Under 50ms on local disk. No blocking, no network.

### Implementation B: Preference Mutation Detector

Detects preference-setting intent, writes `project.yaml`, and confirms via `additionalContext`:

```bash
PROMPT=$(jq -r '.prompt' <<<"$INPUT")

if echo "$PROMPT" | grep -qiE '(always use|set|default to|change to) (squash|merge|rebase)( on | for )?(main|develop)?'; then
  METHOD=$(echo "$PROMPT" | grep -oiE '(squash|merge|rebase)' | head -1 | tr '[:upper:]' '[:lower:]')
  BRANCH_TARGET=$(echo "$PROMPT" | grep -oiE '(main|develop)' | head -1)
  if [[ -n "$BRANCH_TARGET" ]]; then
    yq e ".preferences.pr.branches.$BRANCH_TARGET.merge_method = \"$METHOD\"" -i config/project.yaml
    MSG="[xgh] Wrote pr.branches.$BRANCH_TARGET.merge_method=$METHOD to config/project.yaml"
  else
    yq e ".preferences.pr.merge_method = \"$METHOD\"" -i config/project.yaml
    MSG="[xgh] Wrote pr.merge_method=$METHOD to config/project.yaml"
  fi
  jq -n --arg ctx "$MSG" '{"additionalContext": $ctx}'
  exit 0
fi
```

This directly addresses the scenario that motivated the current branch (`fix/release-squash`): a user saying "use squash on main" during a conversation should propagate to config without a separate edit step.

### Implementation C: Skill Validator / Blocker

Before Claude processes `/xgh-release`, validate that the required conditions are met (clean working tree, on a non-main branch) and block with a helpful message if not:

```bash
if echo "$PROMPT" | grep -qE '^/xgh-release|^/release'; then
  if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
    jq -n '{"action":"block","reason":"Cannot release: working tree is dirty. Commit or stash changes first."}'
    exit 0
  fi
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$BRANCH" == "main" ]]; then
    jq -n '{"action":"block","reason":"Cannot run /release directly on main. Create a release branch from develop first."}'
    exit 0
  fi
fi
```

This prevents the skill from running in an invalid state, giving instant feedback rather than a confusing mid-skill failure.

---

## Summary

`UserPromptSubmit` is xgh's earliest intervention point in the Claude Code pipeline. Its highest-value applications for xgh are:

1. **Ambient context injection** — closing the gap between `config/project.yaml` and every conversation turn without user effort.
2. **Preference mutation detection** — making "say it once in conversation, have it persist to config" real.
3. **Pre-flight validation** — blocking skill invocations that would fail anyway, with actionable messages.

The primary constraint is latency. Every implementation must stay under ~100ms, use local I/O only, and avoid regex patterns broad enough to produce false positives. The hook should be treated as a read-mostly system: prefer enriching context over mutating state, and always log mutations to a debug trail.
