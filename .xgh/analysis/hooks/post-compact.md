---
hook: PostCompact
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# PostCompact Hook — Analysis for xgh

## 1. Hook Spec

**When it fires:** After Claude Code completes a context compaction event — either `manual` (user explicitly triggered `/compact`) or `auto` (Claude Code hit its context window threshold and compacted automatically). Importantly, auto-compaction can happen mid-task without the user noticing, making this hook more consequential than it might appear.

**Input received:** A compaction summary — a condensed prose description of what was in context before compaction. The summary is Claude's own distillation of the session so far: goals, decisions made, files touched, state accumulated.

**Output it can return:** An `additionalContext` string that gets injected into the fresh context window immediately after compaction. This is the hook's primary lever — it cannot prevent compaction or alter the summary, but it can append structured content that the next Claude turn will see as part of its starting context.

---

## 2. Capabilities

**Re-inject critical context.** After compaction, Claude starts fresh from the summary. Any preferences, conventions, or state that were established in earlier turns and not captured in the summary are silently lost. PostCompact can re-supply that material deterministically from files on disk — not from memory.

**Restore active config state.** Shell-computed values (e.g., what `load_pr_pref` resolved for the current branch, what `xgh_config_get` returned) are volatile — they exist only in tool output from earlier turns. PostCompact can re-run those reads and surface their resolved values into the new context.

**Re-warm skill awareness.** Skills that read `config/project.yaml` at invocation time are fine, but Claude's *understanding* of what preferences exist — which informs how it interprets user requests before invoking a skill — can erode after compaction. The hook can re-establish that ambient awareness.

---

## 3. Opportunities for xgh

xgh's core promise is **declarative AI ops**: declare preferences once in `config/project.yaml`, and every agent platform converges to match. This promise is undermined by compaction if the preferences injected at SessionStart are discarded before the session ends.

**Opportunity A — Config reminder injection.** PostCompact reads `config/project.yaml` and emits a compact YAML block under a `## Active xgh Preferences` heading. This restores the preferences registry that SessionStart originally injected, without the full AGENTS.md prose overhead. Skills like `/release` and `/merge-pr` rely on `preferences.pr.merge_method` and `preferences.pr.base_branch` — losing these mid-session causes silent fallback to defaults that may contradict the declared config.

**Opportunity B — Branch-resolved PR preference echo.** `load_pr_pref` implements a read priority: CLI flag > branch override > project default > auto-detect. By the time compaction fires, the resolved value for the current branch may have been established in an earlier turn and is now gone. PostCompact can re-run `load_pr_pref` for the current branch (obtained via `git branch --show-current`) and inject the *resolved* values, not just the raw config — eliminating re-resolution ambiguity in the new window.

**Opportunity C — Context Tree anchor.** xgh's Context Tree (`.xgh/context-tree/`) is the human-readable knowledge base. After compaction, Claude may no longer know the tree exists or where to look. A PostCompact hook can inject the top-level index of the context tree (a small list of categories and their paths) so that subsequent skill invocations know where to find and store context.

---

## 4. Pitfalls

**Re-inflation risk.** Compaction fires because the context was too large. A PostCompact hook that re-injects megabytes of documentation defeats the purpose. The `additionalContext` output must be aggressively minimal — target under 500 tokens. Prefer key:value summaries over prose explanations.

**Staleness.** If `config/project.yaml` was modified during the session (e.g., by a skill that writes back resolved preferences), the hook must read the current file state, not a cached snapshot. Always read from disk at hook execution time.

**Noise for unrelated sessions.** Not every xgh session involves PR operations. Injecting PR merge preferences into a session that's doing context-tree maintenance adds noise. The hook should inspect the compaction summary for signals about what the session is doing and inject only relevant preference namespaces.

**Hook execution environment.** PostCompact runs in the project root with access to the filesystem but not to prior tool outputs. It cannot introspect what skills were invoked before compaction. Design the hook to be stateless — derive everything from files on disk (`config/project.yaml`, `git branch --show-current`, `.xgh/context-tree/`), never from assumed prior state.

---

## 5. Concrete Implementations

### Implementation 1 — Minimal config reminder (high value, low cost)

A PostCompact hook that runs `cat config/project.yaml` filtered to the `preferences:` block and formats it as a fenced YAML block with a header:

```
## xgh config reminder (post-compaction restore)
Preferences declared in config/project.yaml:
<yaml block of preferences section only>
Skills MUST read these as defaults. User can override at call time.
```

Estimated output: ~200 tokens. Covers the most compaction-vulnerable use case (skills forgetting declared merge method, reviewer, or base branch) at negligible context cost.

### Implementation 2 — Branch-aware PR preference resolver

A PostCompact hook that:
1. Runs `git branch --show-current` to get the active branch.
2. Calls `load_pr_pref merge_method "" "$BRANCH"` and `load_pr_pref base_branch "" "$BRANCH"`.
3. Emits the *resolved* values (not the raw config), labeled clearly as "resolved for current branch."

This closes the gap where auto-compaction fires mid-PR-workflow and the next turn re-runs a skill with wrong defaults because the branch override from earlier in the session was lost.

### Implementation 3 — Context Tree index anchor

A PostCompact hook that emits the directory listing of `.xgh/context-tree/` as a compact index:

```
## xgh Context Tree (post-compaction anchor)
Knowledge base at .xgh/context-tree/:
  decisions/   — architectural and design decisions
  patterns/    — recurring code and process patterns
  sessions/    — per-session summaries
  ...
Use ctx_execute_file or Read to access entries. Always write new context here, not to ad-hoc files.
```

This costs ~100 tokens and prevents the common post-compaction failure mode where Claude writes context to arbitrary locations because it forgot the canonical store exists.
