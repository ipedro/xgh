---
title: "LCM — Lossless Context Management Architecture"
category: discovery
domain: ecosystem/lossless-claw
importance: 85
maturity: validated
tags: [DAG, hierarchical-memory, SQLite, context-compaction, summarization, LCM, lossless-claw]
keywords: [DAG, leaf-summary, condensed-summary, compaction, fresh-tail, lcm_expand_query]
updatedAt: "2026-03-16"
source: "https://github.com/martian-engineering/lossless-claw"
paper: "https://papers.voltropy.com/LCM"
---

## Raw Concept

LCM (Lossless Context Management) replaces sliding-window context truncation with a SQLite-backed DAG of hierarchical summaries.

**DAG node types:**
- **Leaf** (depth 0): ~800-1200 tokens, summarizes a chunk of raw messages
- **Condensed** (depth 1+): ~1500-2000 tokens, summarizes N same-depth summaries (N ≥ `LCM_CONDENSED_MIN_FANOUT`, default 4)

**Compaction modes:**
- Incremental (after each turn): leaf pass if unsummarized tokens > threshold
- Full sweep: repeated leaf + condensation passes until under budget
- Budget-targeted: full sweeps until under context token limit

**Three-level summarization escalation per attempt:**
1. Normal — standard prompt, temp 0.2
2. Aggressive — durable facts only, temp 0.1, lower target tokens
3. Fallback — deterministic truncation to ~512 tokens

**Context assembly each turn:**
1. All context_items ordered by ordinal
2. Summaries → XML `<lcm_summary>` tags; messages → reconstructed blocks
3. Evictable prefix + protected fresh tail (last N raw messages always included)
4. Fill remaining budget keeping newest, dropping oldest

**Agent tools:**
- `lcm_grep` — regex/FTS5 search over messages and summaries
- `lcm_describe` — inspect a summary or stored file by ID
- `lcm_expand_query` — spawns bounded sub-agent to walk DAG, returns focused answer (≤2000 tokens)
- `lcm_expand` — low-level DAG walker (sub-agents only, prevents recursive spawning)

**Key config vars:**
- `LCM_FRESH_TAIL_COUNT` (default 16) — raw messages always in context
- `LCM_LEAF_CHUNK_TOKENS` (default 20k) — source tokens per leaf pass
- `LCM_CONDENSED_MIN_FANOUT` (default 4) — summaries needed to trigger condensation
- `LCM_INCREMENTAL_MAX_DEPTH` (default 0) — set to -1 for unlimited condensation

## Narrative

lossless-claw is a plugin for OpenClaw that implements the LCM paper (Voltropy). Instead of losing old messages when the context window fills, it persists everything in SQLite and builds a DAG of summaries. Each chunk of raw messages becomes a leaf summary. When enough leaf summaries accumulate, they get condensed into a higher-level node. This creates a tree where the top represents durable, abstract facts and the bottom represents recent, detailed events.

Context each turn is assembled from summaries (XML-wrapped) + the last N raw messages verbatim (the "fresh tail"). Nothing is ever deleted — raw messages stay in the DB and can be recovered via `lcm_expand_query`, which spawns a bounded sub-agent to walk the DAG and answer a focused question with full access to source messages.

The Go TUI (`lcm-tui`) allows manual inspection, repair, rewrite, dissolve, and transplant of summary nodes — treating the DAG as a first-class artifact to maintain.

## Facts

- Every raw message is persisted to SQLite; nothing is ever permanently truncated
- The DAG uses SHA-256 content-addressed summary IDs
- Sub-agent expansion uses delegation grants with TTL to prevent resource abuse
- Files above a size threshold are intercepted and stored separately, replaced by exploration summaries
- Session reconciliation on startup handles crash recovery from JSONL files
- All DB writes are serialized in transactions to prevent corruption
- Based on the Voltropy LCM paper: https://papers.voltropy.com/LCM
