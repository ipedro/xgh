# RTK vs context-mode — Analysis for xgh

> Analysis date: 2026-03-19
> Sources: [rtk-ai/rtk](https://github.com/rtk-ai/rtk) (v0.x, 10.7k stars, 430 commits), [context-mode](https://github.com/mksglu/claude-context-mode) (v1.0.22, Claude Code plugin)

---

## What is RTK

**RTK (Rust Token Killer)** is a high-performance CLI proxy written in Rust that reduces LLM token consumption by 60-90% on common developer commands. It is a single binary with zero dependencies and <10ms overhead per command.

### How it works

RTK sits between the AI agent and the shell. When Claude Code (or OpenCode / Gemini CLI) issues a Bash tool call, RTK's **auto-rewrite hook** intercepts the command and rewrites it to pass through `rtk` before execution. For example, `git status` becomes `rtk git status`.

RTK then applies four strategies to the command output before it enters the context window:

1. **Smart Filtering** — removes noise (comments, whitespace, boilerplate)
2. **Grouping** — aggregates similar items (files by directory, errors by type)
3. **Truncation** — keeps relevant context, cuts redundancy
4. **Deduplication** — collapses repeated log lines with counts

### Supported commands

RTK handles 20+ command families: `git`, `gh`, `cargo`, `cat/head/tail` (via `rtk read`), `rg/grep`, `ls`, `vitest/jest`, `tsc`, `eslint/biome`, `prettier`, `playwright`, `prisma`, `ruff`, `pytest`, `pip`, `go`, `golangci-lint`, `docker`, `kubectl`, `curl`, `pnpm`.

### Key limitations

- **Only intercepts Bash tool calls.** Claude Code's built-in `Read`, `Grep`, and `Glob` tools bypass the hook entirely.
- **Output-level compression only.** RTK compresses what commands return but does not provide a searchable knowledge base or memory layer — the compressed output still enters the context window in full.
- **No persistence across sessions.** Token savings analytics (`rtk gain`) track historical stats, but there is no semantic recall or learning.

### Installation

```bash
brew install rtk          # Homebrew
rtk init --global         # Install auto-rewrite hook for Claude Code
```

### Architecture

- **Language:** Rust
- **Integration:** Claude Code hook (`settings.json` entry), OpenCode plugin, Gemini CLI hook
- **Configuration:** TOML file (`~/.config/rtk/config.toml`)
- **Analytics:** SQLite database (`~/.local/share/rtk/history.db`) tracking per-command token savings
- **Extensibility:** OpenClaw (community rules directory — early stage)

---

## What is context-mode

**context-mode** is a Claude Code MCP server plugin (TypeScript/Node.js) that achieves ~98% context window reduction by sandboxing data processing into isolated subprocesses and indexing outputs into a searchable FTS5/BM25 knowledge base. Large command outputs, log files, API responses, and documentation never enter the context window — only printed summaries and search results do.

### How it works

context-mode operates at a fundamentally different level than RTK:

1. **Sandboxed execution** — Instead of the agent running commands directly via Bash/Read, it calls context-mode's MCP tools (`ctx_execute`, `ctx_execute_file`, `ctx_batch_execute`). Code runs in an isolated subprocess; only `console.log()`/`print()` output enters the context window. The raw data stays in the subprocess.
2. **FTS5 knowledge base** — All sandboxed output is automatically chunked and indexed into an ephemeral SQLite FTS5 database with BM25 ranking. The agent can later search this indexed content via `ctx_search()` with three-tier fallback (Porter stemming, trigram substring, fuzzy Levenshtein).
3. **PreToolUse hook** — Intercepts Bash, Read, WebFetch, and Grep tool calls. Routes curl/wget through `fetch_and_index`, advises using `execute_file` instead of `Read` for analysis, and blocks `WebFetch` in favor of `fetch_and_index`.
4. **URL fetching** — `ctx_fetch_and_index` fetches URLs, converts HTML to markdown (Turndown + GFM), indexes the full content, and returns a 3KB preview. Full content is searchable but never enters context.

### MCP Tools (6 total)

| Tool | Purpose |
|------|---------|
| `ctx_execute` | Run code in sandboxed subprocess (11 languages) |
| `ctx_execute_file` | Read file + process it in sandbox (FILE_CONTENT variable) |
| `ctx_batch_execute` | Run multiple commands + auto-index + search — all in one call |
| `ctx_search` | BM25 search across all indexed content |
| `ctx_index` | Index documentation/content into the knowledge base |
| `ctx_fetch_and_index` | Fetch URL, convert to markdown, index, return preview |

### Key strengths

- **98% context reduction** — measured across 21 benchmark scenarios (376 KB raw data to 16.5 KB context)
- **Searchable knowledge base** — indexed content is retrievable on demand, not lost after initial compression
- **Agent-controlled summarization** — the agent decides what to print (summarize) vs. what to index for later search
- **Multi-language sandbox** — supports JS, TS, Python, Shell, Ruby, Go, Rust, PHP, Perl, R, Elixir
- **Session-scoped** — ephemeral FTS5 database per session (no cross-session persistence by design)

### Key limitations

- **Requires agent cooperation** — the agent must use context-mode tools instead of native tools. The PreToolUse hook helps guide this, but it is advisory, not enforced.
- **No cross-session memory** — the knowledge base is ephemeral; it does not persist between sessions.
- **Overhead per call** — each MCP tool call has latency overhead vs. native Bash execution (subprocess spawn + indexing).
- **Learning curve** — agents need prompt instructions (like the `<context_window_protection>` block) to use context-mode effectively.

---

## Synergy — Do they complement each other?

**Yes, they are complementary and operate at different layers.** There is minimal overlap.

### Different layers of the stack

| Layer | RTK | context-mode |
|-------|-----|-------------|
| **Where it acts** | Between shell and command output (output-level proxy) | Between agent and tool system (MCP tool layer) |
| **What it compresses** | Raw command stdout/stderr before it enters context | The agent's decision about what to read into context at all |
| **How it integrates** | Bash hook — transparent, zero agent cooperation needed | MCP server — requires agent to call context-mode tools |

### How they could work together

1. **RTK compresses what context-mode cannot intercept.** context-mode's PreToolUse hook cannot intercept Claude Code's native `Read`, `Grep`, and `Glob` tools. RTK's Bash hook also cannot intercept these. However, for the Bash commands that *do* flow through both systems, RTK would compress the output first, and then context-mode would further sandbox and index it. This is **double compression** — potentially wasteful but not harmful.

2. **context-mode provides searchability that RTK lacks.** RTK compresses output but the compressed output still enters the context window in full and is not searchable later. context-mode indexes everything into a BM25 knowledge base, making it retrievable on demand without re-running commands.

3. **RTK handles the "leak" commands.** When an agent uses native Bash (not context-mode tools) — which happens despite prompt instructions — RTK ensures those outputs are at least compressed. This is a safety net.

4. **No conflict.** RTK operates as a Bash hook that rewrites commands; context-mode operates as an MCP server. They do not interfere with each other.

### Overlap analysis

The only overlap is on Bash tool calls where both are active: RTK would compress the output, and context-mode would then sandbox/index the already-compressed output. This is redundant but harmless — the net effect is slightly smaller context consumption than either alone.

---

## Comparison Table

| Dimension | RTK | context-mode |
|-----------|-----|-------------|
| **Primary purpose** | Compress command output to reduce token consumption | Sandbox execution + searchable knowledge base to protect context window |
| **Integration method** | Bash hook (transparent rewrite) | MCP server plugin (agent calls tools explicitly) |
| **Context protection** | 60-90% reduction via output filtering | ~98% reduction via subprocess sandboxing + selective summarization |
| **Persistence** | Token analytics in SQLite (no content persistence) | Ephemeral FTS5 knowledge base (session-scoped, no cross-session) |
| **Search capability** | None — compressed output is fire-and-forget | BM25-ranked FTS5 search with Porter stemming + trigram + fuzzy fallback |
| **Agent cooperation required** | None — hook is transparent | High — agent must use ctx_* tools and follow routing rules |
| **Cost** | Free / open source (MIT) | Free / open source |
| **Maturity** | High (10.7k stars, 430 commits, Homebrew formula, multi-platform) | Medium (v1.0.22, active development, Claude Code plugin ecosystem) |
| **xgh fit** | Orthogonal — does not conflict with any xgh component | Core dependency — xgh skills rely on ctx_batch_execute, ctx_search, ctx_execute_file |
| **Language / runtime** | Rust (single binary, zero deps) | TypeScript/Node.js (npm package, MCP server) |
| **Supported tools** | 20+ CLI command families (git, cargo, pytest, etc.) | 6 MCP tools covering execution, search, indexing, fetching |
| **URL/doc handling** | None | fetch_and_index with HTML-to-markdown conversion + BM25 indexing |
| **Cross-session memory** | No | No (by design — that is lossless-claude's job in the xgh stack) |

---

## Pros / Cons

### RTK

**Pros:**
- Zero agent cooperation needed — works transparently via Bash hook
- Extremely low overhead (<10ms per command) thanks to Rust implementation
- Broad command coverage (20+ command families)
- Token savings analytics with `rtk gain` (graphs, history, daily breakdown)
- Single binary, no runtime dependencies
- High community adoption and maturity (10.7k GitHub stars)
- Works with Claude Code, OpenCode, and Gemini CLI

**Cons:**
- Only intercepts Bash tool calls — Claude Code native tools (Read, Grep, Glob) bypass it
- Compressed output still enters context window in full — no searchability
- No knowledge base or retrieval — cannot re-query past command outputs
- Output-level compression has a ceiling (~80% average) vs. context-mode's ~98%
- No URL fetching or documentation indexing capability
- Does not help with the "context window as RAM" problem — only reduces input size

### context-mode

**Pros:**
- ~98% context reduction through subprocess sandboxing
- Searchable FTS5 knowledge base with BM25 ranking — indexed content is retrievable on demand
- Agent-controlled summarization — the agent decides what matters
- URL fetching with HTML-to-markdown conversion and automatic indexing
- Multi-language sandbox (11 languages)
- `batch_execute` combines multiple commands + search in one round trip
- PreToolUse hook provides guidance layer for routing decisions
- Session statistics tracking

**Cons:**
- Requires agent cooperation — effectiveness depends on prompt engineering and agent compliance
- Subprocess spawn overhead per call (higher latency than native Bash)
- Ephemeral — no cross-session persistence (by design)
- Only works with Claude Code (plugin ecosystem)
- Agent may "fall back" to native tools despite routing instructions, reducing effectiveness
- Learning curve for new agents/projects to adopt context-mode patterns

---

## For xgh specifically

### Current state

xgh already deeply integrates with context-mode. The `<context_window_protection>` XML block is injected into sessions, and xgh skills are designed around context-mode's tool hierarchy:

1. **Primary:** `ctx_batch_execute` for research (commands + queries in one call)
2. **Follow-up:** `ctx_search` for drilling into indexed content
3. **Processing:** `ctx_execute` / `ctx_execute_file` for data analysis
4. **Forbidden:** Direct Bash for commands producing >20 lines; Read for analysis; WebFetch entirely

This integration is fundamental to xgh's architecture — it is not a nice-to-have but a core dependency.

### Where RTK fits

RTK would serve as a **safety net layer** for xgh:

1. **Fallback compression** — When the agent bypasses context-mode (uses native Bash despite instructions), RTK ensures output is at least compressed. This happens more often than expected, especially in complex multi-step workflows.
2. **Complementary to context-mode** — For Bash commands that do flow through context-mode, RTK pre-compresses the output before context-mode sandboxes it. The sandbox then processes already-compressed data, which is more efficient.
3. **Analytics** — `rtk gain` provides visibility into token consumption patterns that neither context-mode nor xgh currently offer at the Bash level.

### What RTK does NOT replace

- **context-mode's searchable knowledge base** — RTK has no equivalent
- **context-mode's URL fetching/indexing** — RTK has no equivalent
- **context-mode's sandbox execution model** — RTK only filters output, not execution
- **lossless-claude** — RTK has no cross-session memory
- **xgh's context tree** — RTK has no persistent knowledge store
- **Cipher MCP** — RTK has no semantic vector search

---

## Recommendation

### Verdict: COMPLEMENT (use both)

**Install RTK alongside context-mode as a complementary layer.** They solve different problems at different levels of the stack:

| Layer | Tool | What it does |
|-------|------|-------------|
| L1: Output compression | **RTK** | Compresses raw command output before it enters any pipeline |
| L2: Context protection | **context-mode** | Sandboxes execution, indexes into searchable KB, controls what enters context |
| L3: Session memory | **context-mode FTS5** | Ephemeral per-session search over indexed content |
| L4: Cross-session memory | **lossless-claude** | Persistent episodic + semantic memory across sessions |
| L5: Team knowledge | **xgh context tree + Cipher** | Git-committed markdown KB + vector search |

### Implementation plan

1. **Add RTK to xgh's recommended setup** — mention in `/xgh-setup` or `/xgh-doctor` as an optional optimization
2. **Do NOT make RTK a hard dependency** — it requires Rust/Homebrew and adds install complexity; keep it opt-in
3. **Do NOT replace context-mode with RTK** — context-mode's searchable KB and sandbox model are irreplaceable for xgh's skill architecture
4. **Consider adding `rtk gain` output to `/xgh-brief`** — if RTK is detected, include token savings in the session briefing

### Rationale

- RTK is a transparent, zero-cooperation safety net. It catches the Bash commands that leak past context-mode.
- context-mode is the strategic layer that gives xgh its searchable, indexed, on-demand retrieval capability.
- Together they provide defense-in-depth for context window management: RTK compresses at L1, context-mode sandboxes at L2.
- Neither replaces lossless-claude (L4) or the context tree (L5), which handle cross-session concerns.

### Risk assessment

- **Low risk** — RTK and context-mode do not conflict; worst case is marginal redundancy on Bash commands
- **Low effort** — RTK install is `brew install rtk && rtk init -g` (one-time, global)
- **Medium value** — primary benefit is catching context-mode bypasses and providing token analytics
