---
title: "xgh + LCM Integration Roadmap"
category: decision
domain: ecosystem/lossless-claw
importance: 88
maturity: draft
tags: [xgh, LCM, Cipher, memory-hierarchy, DAG, integration, post-session-compaction, FTS5]
keywords: [memory_depth, post-session, leaf, session-summary, arc, durable, xgh-expand]
updatedAt: "2026-03-16"
---

## Raw Concept

**Layer model (complementary, not competing):**
- LCM: in-session context management (active conversation)
- Cipher/Qdrant: cross-session semantic memory (persistent across conversations)
- Context tree: durable facts (depth 3+, git-committed)

**Proposed Cipher memory hierarchy:**
- `memory_depth=0` → leaf (single exchange summaries)
- `memory_depth=1` → session (full session synthesis)
- `memory_depth=2` → arc (multi-session project themes)
- `memory_depth=3` → durable (timeless facts = context tree)

**Integration ideas ranked by value:**

1. **Post-session compaction** — After each Claude Code session ends, run LCM leaf-summarization over the session JSONL (`~/.claude/projects/*/`) and store as Cipher memories with `depth=0`. Can be a `PostSessionHook`.

2. **Cipher memory hierarchy** — Add `memory_depth` metadata to Cipher entries. `/xgh-analyze` periodically condenses depth-0 leaves → depth-1 session summaries using depth-aware prompts (detailed → abstract).

3. **Context tree as DAG root** — The context tree already functions as depth-3 (durable) memories. Confirms the current architecture is correct shape; just needs the leaf/session layers below it.

4. **FTS5 over context tree** — SQLite FTS5 index over context tree markdown for regex/keyword search alongside Cipher vector similarity. Improves recall for exact strings (function names, error codes, commit hashes).

5. **`/xgh-expand` skill** — Bounded sub-agent (analogous to `lcm_expand_query`) that walks Cipher + context tree to answer a focused question. Uses delegation pattern with token cap.

6. **Depth-aware summarization prompts** — Four prompt tiers for `/xgh-analyze`:
   - Leaf: detailed narrative of recent exchanges
   - Session: session-level synthesis
   - Arc: multi-session project themes
   - Durable: timeless facts only

## Narrative

LCM and xgh are complementary layers. LCM handles in-session context (preventing the conversation from losing old turns within a single Claude Code session). xgh/Cipher handles cross-session memory (what was decided last week, architectural conventions, team context). Running both simultaneously gives full-spectrum memory: nothing is lost in-session, and important things are promoted to cross-session via Cipher.

The most actionable near-term integration is the **post-session compaction hook**: Claude Code already writes JSONL transcripts to `~/.claude/projects/*/`. A hook or scheduled job (via `/xgh-retrieve` or a new `/xgh-compact` skill) could run LCM-style leaf summarization over those transcripts and store the results as Cipher depth-0 memories. This alone would dramatically improve cross-session recall without requiring full LCM integration.

The **Cipher memory hierarchy** (`memory_depth` field) is the medium-term architectural enhancement. Once depth metadata exists, `/xgh-analyze` can run periodic condensation: group related depth-0 leaves → one depth-1 session summary. Over time, depth-1 summaries condense into depth-2 arc memories. The context tree files are already the depth-3 layer.

## Facts

- LCM in-session + Cipher cross-session = full-spectrum memory architecture
- Context tree already functions as depth-3 (durable) in the LCM model
- Claude Code transcripts are at `~/.claude/projects/*/` (JSONL format)
- Post-session compaction is highest-value, lowest-effort integration
- The LCM paper is required reading before implementing hierarchical memory: https://papers.voltropy.com/LCM
- `/xgh-expand` would be the xgh equivalent of `lcm_expand_query`
- FTS5 would complement Cipher vector search for exact-string recall
