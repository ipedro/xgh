# lossless-claw Research Report

**Date:** 2026-03-16
**Source:** https://github.com/martian-engineering/lossless-claw
**Stars:** 2.3k | **Forks:** 166

---

## 1. What Is lossless-claw? What Problem Does It Solve?

**lossless-claw** is a plugin for [OpenClaw](https://github.com/openclaw/openclaw) (a personal AI assistant CLI — "Your own personal AI assistant. Any OS. Any Platform. The lobster way.") that replaces its built-in sliding-window context compaction with a DAG-based summarization system called **LCM (Lossless Context Management)**.

**The problem:** When a conversation grows beyond a model's context window, all AI agents (OpenClaw, Claude Code, etc.) truncate older messages. This means old context is irretrievably lost. The more you work, the less the agent remembers.

**What lossless-claw does instead:**

1. Persists every message in a SQLite database, organized by conversation
2. Summarizes chunks of older messages into summaries using the configured LLM
3. Condenses summaries into higher-level nodes as they accumulate, forming a DAG
4. Assembles context each turn by combining summaries + recent raw messages
5. Provides tools (`lcm_grep`, `lcm_describe`, `lcm_expand`) so agents can search and recall compressed history

Nothing is ever lost. Raw messages stay in the database. Summaries link back to their source messages. Agents can drill into any summary to recover the original detail.

**Based on:** The [LCM paper](https://papers.voltropy.com/LCM) by [Voltropy](https://x.com/Voltropy).

---

## 2. Technical Approach / Architecture

### Data Model

**Conversations and Messages:**
- Messages are persisted to SQLite with full content and metadata
- Each message belongs to a conversation (identified by `conversationId`)
- `context_items` is an ordered list of what gets assembled into model context each turn

**The Summary DAG:**

Two node types:

- **Leaf summaries** (depth 0, kind `"leaf"`): Created from a chunk of raw messages. Linked to source messages via `summary_messages`. Narrative summary with timestamps. ~800–1200 tokens.
- **Condensed summaries** (depth 1+, kind `"condensed"`): Created from a chunk of same-depth summaries. Linked via `summary_parents`. Each depth uses progressively more abstract prompts. ~1500–2000 tokens.

Every summary carries: `summaryId` (SHA-256 of content + timestamp), `conversationId`, `depth`, `earliestAt/latestAt`, `descendantCount`, `fileIds`, `tokenCount`.

### Compaction Lifecycle

**1. Ingestion:**
- `bootstrap` — on session start, reconciles the JSONL session file with LCM DB (crash recovery)
- `ingest`/`ingestBatch` — persists new messages, appends to `context_items`
- `afterTurn` — ingests new messages, evaluates whether compaction should run

**2. Leaf compaction:**
- Collects unsummarized messages outside the "fresh tail"
- Groups into chunks of `LCM_LEAF_CHUNK_TOKENS` (default 20k tokens)
- Calls LLM to summarize each chunk
- Replaces source messages in `context_items` with the new summary

**3. Condensation:**
- Collects leaf or lower-depth summaries that accumulate to the `LCM_CONDENSED_MIN_FANOUT` threshold (default 4)
- Creates a higher-depth summary from them

**Compaction modes:**

| Mode | Trigger | Behavior |
|------|---------|---------|
| Incremental | After each turn | Leaf pass if unsummarized tokens > `leafChunkTokens`; optional condensation up to `incrementalMaxDepth` |
| Full sweep | `/compact` command or overflow | Repeated leaf passes then condensation passes until no more eligible chunks |
| Budget-targeted | Overflow recovery | Full sweeps until context is under target token count |

**Three-level escalation per summarization attempt:**
1. Normal — standard prompt, temperature 0.2
2. Aggressive — tighter prompt, only durable facts, temperature 0.1, lower target tokens
3. Fallback — deterministic truncation to ~512 tokens

### Context Assembly

Each turn:
1. Fetch all `context_items` ordered by ordinal
2. Resolve items: summaries → user messages with XML wrappers; messages → reconstructed from parts
3. Split into evictable prefix + protected fresh tail (last `freshTailCount` raw messages)
4. Compute fresh tail token cost (always included, even if over budget)
5. Fill remaining budget from evictable set, keeping newest, dropping oldest
6. Normalize assistant content to array blocks (Anthropic API compatibility)
7. Sanitize tool-use/result pairing

**XML summary format:** Summaries are inserted as structured XML `<lcm_summary>` tags containing metadata and narrative content.

### Expansion System

For deep recall, agents use `lcm_expand_query` which spawns a **sub-agent**:

1. Agent calls `lcm_expand_query` with a `prompt` + `query` or `summaryIds`
2. If `query` provided, `lcm_grep` finds matching summaries first
3. A **delegation grant** scopes the sub-agent to relevant conversations with a token cap
4. Sub-agent walks the DAG: reads summary content, follows parent links, accesses source messages, inspects stored files
5. Sub-agent returns a focused answer (≤ 2000 tokens by default) with cited summary IDs
6. Grant is revoked; sub-agent session cleaned up

**Security model:** Sub-agents only get `lcm_expand` (not `lcm_expand_query`) to prevent recursive spawning. Grants have TTL.

### Large File Handling

Files above a size threshold are intercepted, stored separately, and replaced with an exploration summary in the conversation. Agents can retrieve full file content via `lcm_describe(id: "file_xxx")`.

### Session Reconciliation

On session start, `bootstrap` reconciles the JSONL session file with the LCM database, importing any messages that exist in the file but not in LCM (crash recovery). This handles the case where OpenClaw crashed before persisting.

### Operation Serialization

All DB writes are serialized (transactions) to prevent corruption during concurrent operations.

---

## 3. Key Components

### TypeScript Plugin (`src/`)

| File | Role |
|------|------|
| `index.ts` | Plugin entry point and registration with OpenClaw |
| `engine.ts` | `LcmContextEngine` — implements `ContextEngine` interface |
| `assembler.ts` | Context assembly: summaries + messages → model context |
| `compaction.ts` | `CompactionEngine` — leaf passes, condensation, sweeps |
| `summarize.ts` | Depth-aware prompt generation and LLM summarization |
| `retrieval.ts` | `RetrievalEngine` — grep, describe, expand operations |
| `expansion.ts` | DAG expansion logic for `lcm_expand_query` |
| `expansion-auth.ts` | Delegation grants for sub-agent expansion |
| `expansion-policy.ts` | Depth/token policy for expansion |
| `large-files.ts` | File interception, storage, exploration summaries |
| `integrity.ts` | DAG integrity checks and repair utilities |
| `transcript-repair.ts` | Tool-use/result pairing sanitization |
| `db/` | SQLite connection, migrations, config resolution |
| `store/` | Conversation store, summary DAG store, FTS5 sanitization |
| `tools/` | `lcm_grep`, `lcm_describe`, `lcm_expand`, `lcm_expand_query` |

### Go TUI (`tui/`)

Interactive terminal UI (built with [Bubbletea](https://github.com/charmbracelet/bubbletea)) for inspecting and maintaining the LCM database:

- Agent/session browser, windowed conversation paging
- Summary DAG tree with depth/kind/token counts
- Context view: exact ordered list the model receives each turn
- **Rewrite** — re-summarize a node with current depth-aware prompts
- **Subtree rewrite** — bottom-up rewrite of entire branch
- **Dissolve** — reverse a condensation, restoring parent summaries
- **Repair** — fix corrupted summaries (fallback truncations)
- **Transplant** — deep-copy summary DAGs between conversations
- **Backfill** — import pre-LCM JSONL sessions
- **Prompt management** — four depth-aware templates (leaf, d1/session, d2/arc, d3+/durable)

### Agent Tools

| Tool | Description |
|------|-------------|
| `lcm_grep` | Search messages/summaries by regex or FTS5 full-text search |
| `lcm_describe` | Inspect a specific summary or stored file by ID |
| `lcm_expand_query` | Spawn sub-agent to walk DAG and answer a focused question |
| `lcm_expand` | Low-level DAG walker (sub-agents only) |

**Escalation pattern:** `lcm_grep` → `lcm_describe` → `lcm_expand_query`

### Configuration

Key environment variables:

| Variable | Default | Effect |
|----------|---------|--------|
| `LCM_FRESH_TAIL_COUNT` | 16 | How many recent raw messages to always include |
| `LCM_INCREMENTAL_MAX_DEPTH` | 0 | Condensation depth after leaf pass (−1 = unlimited) |
| `LCM_LEAF_CHUNK_TOKENS` | 20000 | Max source tokens per leaf compaction pass |
| `LCM_CONDENSED_MIN_FANOUT` | 4 | Same-depth summaries needed before condensation |
| `LCM_CONTEXT_THRESHOLD` | model-specific | Token budget for active context |
| `LCM_DATABASE_PATH` | `~/.openclaw/lcm.db` | SQLite database location |
| `LCM_ENABLED` | true | Disable to fall back to built-in compaction |
| `LCM_MODEL` | configured LLM | Model to use for summarization |

**Recommended starting config:**
```bash
export LCM_FRESH_TAIL_COUNT=32
export LCM_INCREMENTAL_MAX_DEPTH=-1
```

---

## 4. Papers, Specs, and External Resources

- **LCM Paper:** https://papers.voltropy.com/LCM — The academic/technical foundation for the algorithm (PDF; binary in the repo fetch but the URL is the canonical source)
- **Visual explainer:** https://losslesscontext.ai — Animated visualization of how LCM works ("How AI agents remember everything")
- **Voltropy on X:** https://x.com/Voltropy — The research org that authored the LCM paper
- **OpenClaw:** https://github.com/openclaw/openclaw / https://openclaw.ai — The host agent platform
- **Martian Engineering:** https://github.com/martian-engineering — The org maintaining lossless-claw

**Internal specs (in `specs/` directory):**
- `depth-aware-prompts-and-rewrite.md` — Design for depth-tiered summarization prompts
- `env-config-extraction.md` — Config extraction from env vars
- `extraction-plan.md` — Plan for knowledge extraction
- `historical-session-backfill.md` — Design for backfilling pre-LCM sessions
- `lossless-claw-rename-spec.md` — Naming/rename decisions
- `summary-presentation-and-depth-aware-prompts.md` — How summaries are presented to the model

**Documentation:**
- `docs/architecture.md` — Full architecture reference
- `docs/agent-tools.md` — Tool reference for `lcm_grep`, `lcm_describe`, `lcm_expand_query`
- `docs/configuration.md` — Configuration guide and tuning guide
- `docs/tui.md` — TUI reference
- `docs/fts5.md` — Enabling FTS5 for fast full-text search in SQLite

---

## 5. How This Applies to xgh

xgh is a Claude Code AI tooling system with:
- **Cipher MCP** for semantic vector memory via Qdrant
- **Context tree** of markdown files in git
- **Multi-backend LLM inference**
- **Skills/slash commands**
- **Per-project/team memory** (persistent across sessions)

### Direct relevance and transferable ideas

**A. The DAG summarization model is the key insight**

xgh currently stores memories as flat vector embeddings in Qdrant (via Cipher). The LCM approach adds a *hierarchical* layer: leaf summaries → session summaries → arc summaries → durable facts. This is directly analogous to how humans compress memories — recent events in detail, older events as higher-level abstractions.

**Opportunity:** xgh could layer a DAG-based compaction pass on top of Cipher. When a Claude Code session ends, the session transcript could be:
1. Leaf-summarized (recent exchanges → leaf nodes in Qdrant)
2. Condensed over time (multiple leaf nodes → a session-level summary)
3. Further condensed (multiple sessions → an arc/project-level summary)

**B. The fresh tail concept**

LCM always includes the last N raw messages verbatim regardless of budget. For xgh, this maps to: always inject the last N context-tree entries or the current task's recent Cipher memories without compaction.

**C. Sub-agent expansion pattern**

`lcm_expand_query` spawns a bounded sub-agent to walk the DAG and answer a focused question. xgh's `/xgh-retrieve` skill does something similar but without the DAG traversal structure. The bounded sub-agent with delegation grants + token caps is a useful security/resource pattern for xgh's multi-agent skills.

**D. Searchable by content, not just semantics**

LCM provides `lcm_grep` (regex + FTS5) alongside semantic summaries. xgh relies almost exclusively on vector similarity search in Qdrant. Adding a regex/FTS5 layer over the context tree markdown files would improve recall for exact strings (function names, error codes, commit hashes).

**E. The repair/maintenance TUI approach**

`lcm-tui` lets you inspect, repair, dissolve, and rewrite summaries. xgh lacks any tooling for inspecting/correcting Cipher memory quality. A `/xgh-doctor` extension (beyond the current health-check role) that could inspect vector memories, flag low-quality entries, and trigger re-summarization would be valuable.

**F. Depth-aware prompts**

LCM uses four template tiers:
- Leaf (recent): detailed narrative
- d1 (session): session-level synthesis
- d2 (arc): project arc / multi-session themes
- d3+ (durable): timeless facts only

xgh's Cipher memory doesn't explicitly distinguish these tiers. Adding a `memory_depth` field to Cipher entries and using tier-appropriate prompts when creating summaries would improve memory quality at every level.

**G. Per-conversation storage scope**

LCM scopes everything to `conversationId`. xgh already scopes to project (via `projectId` in Cipher metadata). The LCM model could inform a more granular scoping: `projectId` → `sessionId` → `conversationId`, allowing cross-session and cross-project recall with explicit scope promotion.

### Specific xgh integration ideas

1. **Post-session LCM pass:** After each Claude Code session ends, run a compaction pass over the session JSONL (Claude Code stores transcripts in `~/.claude/projects/*/`) using the LCM leaf summarization approach and store results as Cipher memories with `depth=0`.

2. **Cipher memory hierarchy:** Introduce `memory_depth` metadata in Cipher: `0=leaf`, `1=session`, `2=arc`, `3=durable`. Use `/xgh-analyze` to periodically condense leaf memories into higher-level summaries.

3. **Context tree as the DAG root:** The context tree markdown files already function as "durable" (depth 3+) memories. LCM's framework confirms this is the right shape — the context tree is the durable layer, Cipher is the leaf/session layer.

4. **FTS5 over context tree:** Add a SQLite FTS5 index over the context tree markdown files for fast regex/keyword search, complementing Cipher's vector similarity search.

5. **`/xgh-expand` skill:** A new skill analogous to `lcm_expand_query` that spawns a bounded sub-agent to deep-recall from Cipher + context tree and return a focused answer.

### Assessment

lossless-claw is the most mature public implementation of hierarchical conversation memory for AI agents. The core DAG + depth-aware summarization + sub-agent expansion pattern is directly applicable to xgh. The main difference is that LCM works at the *active context* level (in-session), while xgh works at the *cross-session* level. These are complementary layers, not competing approaches.

The ideal xgh architecture would run LCM *inside* each Claude Code session (handling in-session context), with xgh's Cipher layer handling cross-session persistence. The LCM paper from Voltropy (https://papers.voltropy.com/LCM) is required reading before implementing any hierarchical memory enhancement to xgh.
