---
title: Gap Analysis — Real-World Session 2026-03-19
importance: 9
maturity: validated
---

# xgh Gap Analysis — Session 2026-03-19

Observed during a real work session (tr-ios project). All tools individually functional but orchestration has 7 gaps.

## Critical

**Gap 1 — Scheduler never starts.** `XGH_SCHEDULER` and `XGH_BRIEFING` default to `off`. Neither the installer nor `/xgh-init` sets them. The entire automated pipeline (retrieve every 5m, analyze every 30m, auto-brief) is dead on arrival. Fix: installer or `/xgh-init` should configure these, not require manual `~/.zshenv` editing.

## High

**Gap 2 — Cipher extraction silently fails.** `cipher_extract_and_operate_memory` returns `extracted: 0` for complex content (>500 chars, markdown, tables). The `cipher-pre-hook.sh` correctly warns and points to `/store-memory` skill, but agent uses raw `storeWithDedup` instead — bypassing TTL, routing, dedup, and content type tagging.

**Gap 3 — Dual memory system with conflicting guidance.** Two `UserPromptSubmit` hooks fire simultaneously: `xgh-prompt-submit.sh` (says use `lcm_*`) and `continuous-learning-activator.sh` (says use `cipher_*`). Different APIs for different systems. Agent gets ambiguous guidance every prompt.

**Gap 6 — Ollama not monitored.** 12 failed memories from a silent Ollama outage. No health check, no alert, no auto-retry. Only discovered when manually running `/xgh-analyze`.

## Medium

**Gap 4 — Cursors not updated after retrieve.** `ingest.yaml` cursors stale after manual `/xgh-retrieve`. Next run re-processes old messages (dedup handles it but wastes tokens).

**Gap 7 — Custom skills have no trigger.** Skills that say "run periodically" but have no CronCreate call — purely manual even if scheduler is on.

## Low

**Gap 5 — Retention never enforced.** `retention.inbox_processed: 7d` configured but nothing prunes `~/.xgh/inbox/processed/` (38 files, oldest 15 days). No launchd, no cron, no hook.

## What worked

- Manual skill invocations (index/analyze/retrieve)
- Slack MCP reading (4 channels + threads)
- context-mode (ctx_batch_execute, ctx_execute) — protected context window
- cipher-pre-hook.sh complex detection — diagnosed every failure
- lossless-claude restore at SessionStart — episodic context loaded
- Context tree at session start (20 files indexed)
- RTK command rewriting — token savings applied
- xgh-post-edit.sh edit tracking — context health state maintained

## Root pattern

The tools work. The glue doesn't activate them. xgh's installer configures everything but leaves the engine off. The cockpit has all the instruments but the ignition key (`XGH_SCHEDULER=on`) is hidden in a manual step.
