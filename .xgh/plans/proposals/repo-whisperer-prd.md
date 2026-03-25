# Repo Whisperer -- Product Requirements Document

**Feature:** Repo Whisperer (git history as living context for xgh)
**Author:** Pedro (via Claude Code)
**Date:** 2026-03-15
**Status:** PRD -- ready for engineering review
**Proposal Source:** [`context-sources.md`](./context-sources.md)

---

## 1. Overview

### 1.1 Problem Statement: The Amnesia Tax

AI coding agents treat every codebase as a snapshot -- a frozen artifact with no history. They can read the code that exists right now but cannot understand how it got there. When an agent encounters a non-obvious implementation, it has no way to discover:

- The **commit message** explaining the tradeoff ("chose O(n^2) because n < 10 and readability matters more")
- The **PR discussion** where three engineers debated the approach and the tech lead made the call
- The **reverted commit** that tried the "obvious" approach and broke production
- The **code review comment** warning "don't change this without updating the mobile client"

**Quantified impact:**

| Metric | Value | Source |
|--------|-------|--------|
| Time lost per "why is it like this?" investigation | 10-30 minutes | Developer self-report (git blame, PR archaeology, Slack search) |
| Investigations per developer per week | 3-5 | Typical on a mature codebase |
| Weekly time wasted per developer | 30-150 minutes | Low/high estimates |
| Regressions from re-proposing rejected approaches | 1-2 per sprint per team | Post-mortem analysis |
| Onboarding time for new contributor (OSS) | Days to weeks | Historical context is the slowest part |
| Cost of a single reintroduced bug (payments example) | Hours to days | Debugging + rollback + incident response |
| Annual cost per developer (at 60 min/week avg) | ~52 hours | 52 weeks x 60 min |

The irony: the codebase already has a memory. It is encoded in git -- commit messages, PR threads, code review comments, merge conflict resolutions. But agents cannot read it. Today, the only option is for a human to manually transcribe this context into CLAUDE.md or the context tree. That does not scale. The history is already there, sitting in git, unread.

### 1.2 Vision

With Repo Whisperer, agents understand the codebase as a **narrative**, not a snapshot. Every commit message, PR discussion, code review comment, and revert becomes searchable semantic memory. The agent stops proposing changes that were already tried and rejected, stops refactoring code with hidden constraints, and starts answering "why is the code like this?" with the actual historical answer.

**Before Repo Whisperer:**
```
Developer asks "why is this retry logic manual?" -> Agent guesses based on code -> Agent
proposes "use the retry library" -> That was tried in PR #847 and caused duplicate charges ->
Developer debugs for 2 days -> Discovers the PR that explains everything
```

**After Repo Whisperer:**
```
Developer asks "why is this retry logic manual?" -> Agent searches git history memory ->
Agent responds: "PR #847 tried the retry library but it caused duplicate charges on
non-idempotent POSTs. Bug PAYMENTS-2341 is still open. Check before switching back." ->
Developer avoids the trap in 15 seconds
```

### 1.3 Success Metrics

| Metric | Current Baseline | Target | Measurement Method |
|--------|-----------------|--------|-------------------|
| Time-to-answer for "why is this code like this?" | 10-30 min (manual git archaeology) | <30 seconds (agent query) | Timestamp delta: question asked to answer rendered |
| Regression rate from re-proposing rejected changes | Unmeasured but reported | 50% reduction in first 30 days | Track agent suggestions that match reverted commits |
| Contributor onboarding time (OSS) | Days to first meaningful PR | <1 hour to understand module history | Time from `/xgh-whisper --bootstrap` to first "why" question answered |
| History coverage (% of significant decisions captured) | 0% (no ingestion) | >80% of commits with non-trivial messages | Ratio of ingested vs. total commits with substantive messages |
| Bootstrap ingestion time (500 commits) | N/A | <5 minutes | Wall-clock time for `/xgh-whisper --bootstrap` |
| Incremental ingestion time (per session) | N/A | <500ms for <50 new commits | Wall-clock time during `session-start` hook |
| Context tree decision files created | 0 | 10+ high-confidence decisions per 500 commits | Count of files in `.xgh/context-tree/repo-history/decisions/` |
| Developer satisfaction (query relevance) | N/A | >80% of Whisperer results rated useful | Agent query results that user acts on vs. ignores |

---

## 2. User Personas & Stories

### 2.1 Solo Dev -- "The Past-Self Archaeologist"

**Persona:** Alex, a developer who works on personal projects in evenings and weekends. They are both the author and the audience of their own git history.

**Before:** Alex returns to a side project after 3 months. They find a function with a cryptic workaround and a TODO comment that says "needed for Safari compat." They spend 20 minutes in `git blame` and `git log` trying to remember what Safari bug this was about, whether it is still relevant, and whether they can safely remove it. They cannot find the original commit because it was squash-merged.

**Story:** As a solo developer, I want my AI agent to surface the historical reasoning behind my own past code decisions, so that I can safely modify code I wrote months ago without reintroducing bugs my past self already fixed.

**After:** Alex asks their agent: "What's this Safari workaround about?" Repo Whisperer responds: "You added this in commit `b3e2a1` (2025-10-14). Your commit message says 'Safari 16.x drops the `focus-visible` pseudo-class on custom elements after a re-render. Workaround: force a style recalculation via `offsetHeight` read.' WebKit bug #248317 was fixed in Safari 17.2. You can remove the workaround if your minimum Safari target is 17.2+." Alex removes it with confidence in 30 seconds.

**Delight factor:** Having a "past self" that remembers perfectly. The agent becomes a time machine for your own decisions.

---

### 2.2 OSS Contributor -- "The Context-Starved Newcomer"

**Persona:** Jordan, an open-source contributor who wants to contribute to a popular library. They have zero historical context -- no Slack history, no meeting notes, no tribal knowledge.

**Before:** Jordan finds an open issue and starts working on a PR. They propose using a newer API that simplifies the implementation. The maintainer rejects the PR: "We discussed this in #847 and decided against it because of backwards compatibility with Node 16 users." Jordan wasted a day implementing an approach the team had already evaluated and rejected. The maintainer is frustrated -- this is the third time a new contributor has proposed this.

**Story:** As an OSS contributor with no historical context, I want my AI agent to surface past discussions, rejected approaches, and team conventions from the repository's git and PR history, so that I can contribute effectively without repeating debates the team has already settled.

**After:** Before Jordan starts coding, their agent (bootstrapped with Repo Whisperer) warns: "This area has 3 past PRs that proposed similar changes (#847, #901, #932). All were closed. The consensus from PR #847 discussion: backwards compatibility with Node 16 is a hard requirement until v5.0. Detected convention: new APIs must have a polyfill path for Node 16." Jordan pivots their approach and submits a PR that gets merged on the first review.

**Delight factor:** Feeling like a team insider on day one. The maintainer sees a contributor who "gets it" and is delighted instead of frustrated.

---

### 2.3 Enterprise -- "The Institutional Memory Keeper"

**Persona:** Priya, a senior engineer on a team with high turnover. The person who wrote the authentication layer left 6 months ago. Their reasoning lives in git and PR threads, but nobody reads them.

**Before:** Priya's team is migrating the auth layer from session tokens to JWTs. A junior engineer proposes using `HS256` for JWT signing because "it's simpler." Nobody on the current team remembers that the original auth author explicitly chose `RS256` in PR #312 because the mobile client validates tokens locally and cannot hold symmetric secrets. The team ships `HS256`, the mobile client breaks in production, and the incident takes 2 days to resolve.

**Story:** As an enterprise engineer on a team with institutional knowledge loss, I want my AI agent to surface the reasoning of past team members from PR discussions and code review comments, so that critical design decisions survive team turnover and are not silently reverted.

**After:** When the junior engineer proposes `HS256`, the agent flags: "PR #312 (author: @previous-dev, 2025-06-18) contains a detailed discussion about signing algorithms. The decision was RS256 because: (1) mobile client validates tokens locally, (2) symmetric secrets cannot be safely distributed to mobile, (3) RS256 allows key rotation without client updates. 4 reviewers approved. This decision is tagged as a `constraint` in Repo Whisperer." The junior engineer adjusts their approach before writing any code.

**Delight factor:** Institutional knowledge that survives team turnover. The team's collective wisdom becomes durable, not ephemeral.

---

### 2.4 OpenClaw -- "The Personal Engineering Journalist"

**Persona:** Sam, who uses xgh's OpenClaw archetype as a personal AI assistant. They work across several personal repos -- a home automation project, a personal finance tracker, a hobby game engine.

**Before:** Sam asks "What was I working on in the home automation repo last month?" and has to manually read through `git log`, trying to piece together a narrative from terse commit messages and forgotten branches.

**Story:** As an OpenClaw user, I want my AI agent to synthesize my git history into a queryable engineering journal, so that I can ask natural-language questions about my own development activity and get narrative answers.

**After:** Sam asks: "Show me every decision I made about the database schema in the finance tracker." Repo Whisperer responds: "You made 4 schema decisions in the last 3 months: (1) Switched from SQLite to PostgreSQL in commit `a2f3b1` for concurrent access. (2) Added `deleted_at` soft-delete column in PR #12 after accidentally losing records. (3) Denormalized the `transactions` table in commit `c4d5e6` because JOINs were slow on your Raspberry Pi. (4) Reverted the denormalization in commit `f7g8h9` after adding proper indexes solved the perf issue." Sam has a perfect engineering journal they never had to write.

**Delight factor:** An engineering autobiography generated from git. Every repo becomes a story you can query.

---

## 3. Requirements

### 3.1 Must Have (P0) -- Core Extraction & Memory

These requirements form the minimum viable Repo Whisperer. Without all of them, the feature does not deliver its core promise.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **RW-P0-01** | **Git log extractor:** Parse commit messages, author, date, and files changed from local git history. No API calls required. | Runs `git log` with configurable depth (default: 500 commits). Extracts: `hash`, `author`, `date`, `message`, `files_changed[]`. Handles merge commits, squash commits, and conventional commit formats. Output is structured JSON. |
| **RW-P0-02** | **Diff-hunk extractor:** Pair significant code changes with their commit messages to create "change narratives" -- what changed and why, together. | For each commit, extracts diff summary (files changed, insertions, deletions). Pairs with commit message to create a combined narrative chunk. Skips trivial changes (whitespace-only, auto-generated files). Configurable file exclusion patterns (default: `*.lock`, `*.generated.*`, `node_modules/`). |
| **RW-P0-03** | **Chunker & Classifier:** Split raw extractions into semantic chunks and classify each one. | Classifications: `decision`, `tradeoff`, `constraint`, `convention`, `bug-fix-rationale`, `revert-reason`, `refactor-motivation`, `context-note`. Each chunk has: `source_type`, `file_paths[]`, `authors[]`, `date`, `classification`, `confidence_score`. Minimum confidence threshold configurable (default: 0.6). |
| **RW-P0-04** | **Cipher memory storage:** Store processed chunks in Cipher (Qdrant vectors) with rich metadata. | Each chunk stored with metadata: `type: repo-whisperer`, `source_type` (commit/pr/review), `classification`, `file_paths`, `authors`, `date`, `commit_hash`. Queryable via `cipher_memory_search` with metadata filtering. |
| **RW-P0-05** | **Context tree output:** Write high-confidence decisions and conventions to the context tree as human-readable markdown files. | Decisions written to `.xgh/context-tree/repo-history/decisions/{hash}-{slug}.md`. Conventions written to `.xgh/context-tree/repo-history/conventions/{slug}.md`. Files follow context tree format with frontmatter (`title`, `importance`, `maturity: draft`, `category: decision|convention`). Only written when confidence > 0.8. |
| **RW-P0-06** | **Deduplication layer:** Prevent re-ingesting commits already in memory. | Tracks HEAD position per branch in `.xgh/whisperer/state.yaml`. On incremental ingestion, only processes commits newer than the tracked HEAD. On bootstrap, checks existing Cipher entries by `commit_hash` before storing. |
| **RW-P0-07** | **Bootstrap mode:** Full history ingestion via `/xgh-whisper --bootstrap`. | Configurable depth (default: 500 commits, flag: `--depth N`). Progress indicator during ingestion. Stores processing state for resume-on-failure. Completes in <5 minutes for 500 commits on a typical machine. |
| **RW-P0-08** | **Incremental mode:** Automatic ingestion of new commits since last session. | Triggered by `session-start.sh` hook when new commits detected. Processes only commits since the last tracked HEAD. Background execution: does not block session start. Budget: <500ms for <50 new commits. |
| **RW-P0-09** | **Targeted mode:** Deep-dive into a specific file or directory's history. | `/xgh-whisper <file-or-path>` ingests the full history of the specified path. Uses `git log --follow <path>` to track renames. Stores with file path metadata for targeted retrieval. |
| **RW-P0-10** | **`/xgh-whisper` skill:** Main entry point skill file and slash command. | Skill: `skills/whisperer/whisperer.md`. Command: `commands/whisper.md`. Supports `--bootstrap`, `--file <path>`, and bare invocation (incremental). Output uses xgh markdown style with classification badges. |
| **RW-P0-11** | **Configuration:** Whisperer config in `.xgh/config.yaml` under `modules.whisperer`. | Keys: `enabled` (bool), `ingestion_depth` (int, default 500), `branch_filters` (list, default all), `file_exclusions` (list, default lockfiles and generated), `classification_threshold` (float, default 0.6), `context_tree_threshold` (float, default 0.8). |
| **RW-P0-12** | **techpack.yaml registration:** Whisperer components registered in `techpack.yaml`. | New component IDs: `whisperer-skill`, `whisperer-command`, `whisperer-config`. Components follow existing schema patterns in `techpack.yaml`. |
| **RW-P0-13** | **Graceful degradation without GitHub/GitLab PAT:** Repo Whisperer works with local git history only when no API access is available. | All P0 features function using only local `git` commands. No network calls required. PR extraction (P1) is additive, not required. |

### 3.2 Should Have (P1) -- PR Threads & Enhanced Intelligence

These features add the "discussion layer" -- the richest source of historical context.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **RW-P1-01** | **PR thread extractor:** Pull PR descriptions, review comments, and inline code comments from GitHub/GitLab. | Uses GitHub MCP (`gh` CLI) or GitLab API. Extracts: PR title, description, review comments (with file/line anchors), approval/rejection signals, linked issues. Requires PAT or MCP integration. Falls back gracefully if unavailable. |
| **RW-P1-02** | **Decision Extractor:** Identify moments where alternatives were weighed in PR discussions. | Detects patterns: disagreement followed by resolution, "I tried X but Y because Z", explicit approval/rejection language, "LGTM with concerns" threads. Creates first-class `decision` objects with `alternatives[]`, `chosen`, `rationale`, `approvers[]`. |
| **RW-P1-03** | **PR mode:** Single-PR deep dive via `/xgh-whisper --pr <number>`. | Ingests the full PR thread: description, all commits, all review comments, all inline comments. Stores as a connected set of chunks with `pr_number` metadata. Output: structured narrative of the PR's discussion arc. |
| **RW-P1-04** | **Git blame integration:** Build authorship and change-frequency maps for files. | For a given file, produces: author attribution per line/section, change frequency heatmap (lines changed per month), "hot zones" (code that changes >3x per quarter). Stored as metadata, queryable via `/xgh-ask --history`. |
| **RW-P1-05** | **`/xgh-ask --history` flag:** Bias search results toward Repo Whisperer memories. | When `--history` is passed, `cipher_memory_search` filters on `type: repo-whisperer` metadata. Results ranked by relevance to the query with file-path boosting when the user is working in a relevant file. |
| **RW-P1-06** | **Convention detection:** Infer coding conventions from patterns in code review comments. | Scans review comments for repeated feedback patterns ("use exhaustive switch", "add error handling", "prefer named exports"). When a pattern appears in >5 PRs, creates a `convention` entry with examples and confidence score. |
| **RW-P1-07** | **Revert intelligence:** When a commit is a revert, link it to the original and store the revert reason. | Detects `Revert "..."` and `This reverts commit ...` patterns. Creates a linked pair: original commit + revert with reason. On future queries about the original code area, surfaces the revert history proactively. |

### 3.3 Nice to Have (P2) -- Future Possibilities

These are features Repo Whisperer enables but does not implement in v1. They are documented to shape architectural decisions.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **RW-P2-01** | **Change impact prediction:** "If I modify this function, what historically broke when it was changed?" | Cross-reference past commits that touched the same code with their associated bug reports, reverts, and hotfixes. Surface as a "risk profile" before modification. |
| **RW-P2-02** | **Onboarding autopilot:** `/xgh-onboard` skill that walks new team members through the project's evolution. | Guided tour: major decisions, architectural direction, active conventions, "things people get wrong." All sourced from Repo Whisperer memory, not stale wiki pages. |
| **RW-P2-03** | **Cross-repo learning:** If the iOS repo's Whisperer knows about an API contract decision, the backend repo's agent can find it. | Requires linked workspaces feature. Whisperer queries linked projects' memories for cross-references by file path or semantic similarity. |
| **RW-P2-04** | **Review assist:** When reviewing a PR, flag code that has documented constraints from past PRs. | Agent checks each changed file against Whisperer `constraint` entries. Flags: "This changes code with a documented constraint from PR #312 -- verify with the original author." |
| **RW-P2-05** | **Velocity analytics:** Module-level decision density and change frequency over time. | "Which modules had the most architectural decisions this quarter?" Ranked by decision count with summaries. Useful for sprint planning and team leads. |
| **RW-P2-06** | **Natural language changelog:** Generate human-readable changelogs from Whisperer memory instead of raw commit logs. | `/xgh-whisper --changelog v2.1..v2.2` produces a narrative changelog grouped by theme (features, fixes, breaking changes) with links to source PRs. |

---

## 4. User Experience

### 4.1 Bootstrap: First Contact

The first time a developer installs Repo Whisperer, they run the bootstrap. This is the "investment" that pays off in every subsequent session.

**Flow:**

```
1. Developer installs xgh and runs /xgh-init (selects archetype)
2. Whisperer module included based on archetype (default: OSS + Enterprise)
3. Developer runs /xgh-whisper --bootstrap
4. Whisperer ingests the last 500 commits (configurable)
5. Progress indicator shows: extracting -> classifying -> storing
6. Summary: "Ingested 487 commits. Found 34 decisions, 12 conventions, 8 constraints.
   Wrote 15 high-confidence entries to the context tree."
7. Developer asks their first "why" question
```

**What the developer sees:**

```markdown
## 🐴 Repo Whisperer -- Bootstrap Complete

**Repository:** my-project | **Depth:** 500 commits | **Time:** 3m 42s

| | |
|---|---|
| **Commits processed** | 487 (13 skipped: empty merge commits) |
| **Chunks created** | 1,247 |
| **Decisions found** | 34 |
| **Conventions detected** | 12 |
| **Constraints identified** | 8 |
| **Context tree files written** | 15 (decisions: 9, conventions: 6) |
| **Storage** | Cipher: 1,247 vectors | Context tree: 15 files (23KB) |

### Top Decisions Found

1. **RS256 over HS256 for JWT signing** (PR #312, 2025-06-18) -- mobile client validates tokens locally
2. **Manual retry over retry library** (PR #847, 2025-11-02) -- library bug with non-idempotent POSTs
3. **PostgreSQL over SQLite** (commit `a2f3b1`, 2025-09-14) -- concurrent access requirements

### Detected Conventions

- Exhaustive switch statements required (seen in 15 code reviews)
- Named exports preferred over default exports (seen in 8 code reviews)
- Error messages must include error codes (seen in 12 code reviews)

🤖 *Try asking: "Why do we have two date formatting functions?" or "What constraints apply to the auth module?"*
```

### 4.2 During a Session: Proactive Context

Repo Whisperer surfaces context proactively when the agent detects the developer is about to modify code with historical significance.

**What the developer sees (when modifying a constrained file):**

```markdown
## 🐴 Whisperer -- Historical Context

> **Before you modify `src/payments/retry.js`:**
>
> This file has **3 documented constraints** from past PRs:
>
> 1. **Do not use the retry library** -- PR #847 (2025-11-02): library has a bug with
>    non-idempotent POST requests that causes duplicate charges. Bug PAYMENTS-2341 is
>    still open.
> 2. **Hardcoded delays are intentional** -- Commit `d4e5f6` (2025-11-03): exponential
>    backoff was tried but the payment gateway rate-limits on rapid retries.
> 3. **Mobile client dependency** -- Code review on PR #312: changes to retry behavior
>    must be coordinated with the mobile team (@mobile-leads).
>
> *Source: Repo Whisperer (git history + PR threads)*
```

### 4.3 Query Response: Answering "Why?"

When the developer asks a historical question, the agent uses Whisperer memory to construct a narrative answer.

**What the developer sees:**

```markdown
## 🐴 Whisperer -- History Query

**Q:** "Why do we have two different date formatting functions?"

**A:** Two date formatters exist because of a backwards-compatibility constraint:

| Function | Origin | Reason |
|----------|--------|--------|
| `formatDate()` | Commit `1a2b3c` (2024-03-10) | Original formatter, uses `Intl.DateTimeFormat`. Works everywhere except legacy API consumers. |
| `formatDateLegacy()` | PR #445 (2024-08-22) | Added for v1 API consumers that expect `MM/DD/YYYY` format. Cannot be removed until v1 API is sunset. |

**PR #567** (2024-11-05) proposed unifying them. It was closed because:
- 12 external API consumers still use v1 format
- Migration guide drafted but not shipped (linked ticket: API-2341, status: backlog)

**Recommendation:** Check if API-2341 has moved. If v1 sunset is scheduled, unification can proceed. Otherwise, keep both.

*Sources: 3 commits, 2 PRs, 1 code review thread*
```

### 4.4 Output Style Guide

Repo Whisperer output follows the xgh convention: scannable, emoji-accented, table-structured.

**Principles:**
- **Narrative over data dump:** Present history as a story, not a list of commits. Developers want "what happened and why," not raw git log.
- **Source attribution always:** Every claim links back to its source (commit hash, PR number, review comment). Trust requires traceability.
- **Actionable over archival:** End every history query with a recommendation or next step. "Here is the history" is less useful than "here is what it means for your current task."
- **Progressive detail:** Summary first, details on request. The initial answer is 3-5 lines. `/xgh-whisper --detail` gives the full narrative.

**Visual elements:**

| Element | Purpose |
|---------|---------|
| `## 🐴 Whisperer --` | Consistent header, distinguishes from other xgh output |
| Classification badges | `[decision]`, `[constraint]`, `[convention]` -- instant categorization |
| Source citations | `PR #847`, `commit a1b2c3` -- trust through traceability |
| Recommendation block | Actionable next step based on the history |
| `🤖` hints | Suggested follow-up queries to teach discovery patterns |

### 4.5 Edge Cases

#### First Bootstrap on a Repo With No Meaningful Commit Messages

**Behavior:** Whisperer processes all commits but classifies most as `context-note` with low confidence. Few or no entries are written to the context tree. The summary honestly reports: "487 commits processed. 3 decisions found (low confidence). Most commit messages are terse. Consider enriching with `/xgh-whisper --pr` if GitHub PRs have better context."

**Why not skip terse commits?** Because even "fix bug" commits contribute to change-frequency maps. The code change itself (diff hunk) paired with the file path is still valuable signal for hot-zone detection.

#### Monorepo With Multiple Teams

**Behavior:** Whisperer uses file path metadata to scope results. When a developer asks about `src/payments/`, results are filtered to commits that touched that path. Cross-cutting commits (those touching multiple paths) appear in all relevant scopes. Path-based filtering is automatic, not requiring configuration.

#### Private/Sensitive Commit Messages

**Behavior:** Whisperer stores commit messages and PR descriptions as-is. It does not apply content filtering. If sensitive information exists in git history, it will be ingested. The privacy boundary is: if it is already in your git history, Whisperer can see it. Organizations with sensitive commit messages should configure `file_exclusions` and branch filters.

#### Squash-Merged PRs

**Behavior:** For squash merges, the individual commit messages from the PR branch are lost in local git history. Whisperer's P1 PR thread extractor recovers the full discussion by querying the GitHub/GitLab API. In P0 (local-only mode), the squash commit message is used as-is -- which typically includes the PR title and number.

---

## 5. Technical Boundaries

### 5.1 Architecture: Three-Layer Pipeline

```
Layer 1: Extractors        Layer 2: Processors       Layer 3: Memory

git log ─────────┐
                 │         ┌─────────────┐
git blame ───────┼────────>│  Chunker &  │   ┌─────────────────┐
                 │         │  Classifier │──>│ Cipher (Qdrant)  │
PR threads ──────┤         └─────────────┘   │ + Context Tree   │
(GitHub/GitLab)  │                │          └─────────────────┘
                 │         ┌──────┴──────┐
review comments ─┤         │  Decision   │   Queryable via
                 │         │  Extractor  │   cipher_memory_search
diff hunks ──────┘         └─────────────┘   and /xgh-ask --history
```

### 5.2 Data Captured and Storage

| Data Point | Storage Location | Retention |
|------------|-----------------|-----------|
| Processed commit chunks (vectors) | Cipher (Qdrant) | Follows Cipher retention policy |
| High-confidence decisions | `.xgh/context-tree/repo-history/decisions/` (git-committed) | Permanent (travels with the repo) |
| Detected conventions | `.xgh/context-tree/repo-history/conventions/` (git-committed) | Permanent (travels with the repo) |
| Ingestion state (HEAD tracking) | `.xgh/whisperer/state.yaml` (git-ignored) | Permanent (local state) |
| Whisperer config | `.xgh/config.yaml` -> `modules.whisperer` | Permanent (config file) |
| Processing log | `.xgh/whisperer/whisperer.log` | 7 days, max 5MB |

**Ingestion state schema:**

```yaml
# .xgh/whisperer/state.yaml (git-ignored, local tracking)
schema_version: 1
last_bootstrap: "2026-03-15T14:00:00Z"       # ISO 8601, null if never bootstrapped
branches:
  main:
    last_ingested_hash: "a1b2c3d"             # HEAD at last ingestion
    last_ingested_date: "2026-03-15T14:32:00Z"
    commits_ingested: 487
  feat/auth-refactor:
    last_ingested_hash: "d4e5f6g"
    last_ingested_date: "2026-03-15T10:15:00Z"
    commits_ingested: 23
total_chunks_stored: 1247
total_decisions_found: 34
total_conventions_found: 12
```

**Context tree output format:**

```markdown
---
title: "RS256 chosen over HS256 for JWT signing"
importance: 85
maturity: draft
category: decision
source_type: pr-discussion
source_ref: "PR #312"
date: "2025-06-18"
authors: ["@previous-dev", "@tech-lead"]
files_affected: ["src/auth/jwt.ts", "src/auth/config.ts"]
---

## Decision

RS256 was chosen over HS256 for JWT signing.

## Context

The mobile client validates JWT tokens locally without calling the backend. This means the
signing key must be asymmetric -- the mobile client holds the public key, the server holds
the private key.

## Alternatives Considered

- **HS256 (symmetric):** Simpler implementation, but requires distributing the shared secret
  to mobile clients, which is a security risk.
- **RS256 (asymmetric):** More complex key management, but the public key can be safely
  embedded in the mobile app and rotated via JWKS endpoint.

## Outcome

RS256 adopted. Key rotation endpoint added at `/auth/.well-known/jwks.json`.

*Extracted by Repo Whisperer from PR #312 discussion (4 reviewers approved).*
```

### 5.3 Privacy: What NEVER Gets Stored

| Excluded Data | Reason |
|---------------|--------|
| Full file contents or complete diffs | Only diff summaries (files changed, insertions/deletions count) and targeted hunks paired with commit messages. Never the full diff. |
| API keys, tokens, credentials | Even if present in commit messages (which they should not be), the classifier filters secrets detected by pattern matching. |
| Git author email addresses | Only git usernames/handles are stored. Emails are stripped during extraction. |
| Contents of `.env` files or secrets directories | Excluded from file path tracking via default `file_exclusions`. |
| Binary file diffs | Binary files are noted as "binary file changed" but no content is extracted. |
| Draft/abandoned branch history | Only branches matching `branch_filters` config are ingested. Default: all branches. |

**Privacy contract:** Repo Whisperer stores **metadata about changes** (who, when, why, which files) and **semantic summaries** of discussions. It does not store raw code content. A Whisperer memory dump would reveal your project's decision history but not your source code.

### 5.4 Performance Budget

| Operation | Budget | Method |
|-----------|--------|--------|
| **Bootstrap ingestion (500 commits)** | <5 minutes | `git log` (~1s) + chunking (~30s) + classification (~3 min via LLM) + Cipher writes (~30s) |
| **Incremental ingestion (<50 commits)** | <500ms total | `git log` delta (~50ms) + chunking (~100ms) + classification (local heuristics for <50) + Cipher writes (~200ms) |
| **Targeted file ingestion** | <30 seconds per file | `git log --follow` (~200ms) + same pipeline |
| **PR mode (single PR)** | <10 seconds | GitHub API call (~1s) + chunking + classification + storage |
| **Query (cipher_memory_search)** | <1 second | Standard Cipher query with metadata filter `type: repo-whisperer` |
| **Proactive context injection** | <200ms | Pre-computed hot-zone lookup from `state.yaml` + Cipher metadata query |
| **Context tree write** | <50ms per file | Markdown template + frontmatter generation |
| **State file update** | <10ms | YAML write to `.xgh/whisperer/state.yaml` |
| **Disk usage (context tree)** | <100KB per 500 commits | Only high-confidence entries written. ~1-2KB per decision/convention file. |

**Non-negotiable:** Incremental ingestion must NEVER block session start. If it exceeds budget, it must run in the background and complete asynchronously.

### 5.5 Interaction With Existing xgh Components

#### Cipher MCP

- **Storage (P0):** Uses `cipher_store_reasoning_memory` to store classified chunks. Each chunk tagged with `type: repo-whisperer` plus classification metadata.
- **Retrieval (P0):** Uses `cipher_memory_search` with metadata filter `type: repo-whisperer` for history queries. The `/xgh-ask --history` flag triggers this filter automatically.
- **No new Cipher capabilities required.** Whisperer uses existing Cipher tools with richer metadata.

#### Context Tree

- **Direct output (P0):** High-confidence decisions and conventions are written to `.xgh/context-tree/repo-history/` as markdown files. These become part of the project's durable knowledge base -- reviewable in PRs, available to all team members.
- **Session-start loading:** Context tree entries from `repo-history/` are loaded by the existing `session-start.sh` hook via the standard importance/maturity scoring. High-importance decisions surface automatically in every session.

#### Ingest Pipeline

- **No interaction in P0/P1.** Repo Whisperer and the ingest pipeline are independent context sources.
- **P2 complement:** Ingest captures external signals (Slack, Jira). Whisperer captures internal signals (git). Together, they provide complete context: "The Slack discussion that led to the PR that changed the code."

### 5.6 Archetype Tiering

| Capability | Solo Dev | OSS Contributor | Enterprise | OpenClaw |
|------------|:--------:|:---------------:|:----------:|:--------:|
| Local git extraction (P0) | Optional add-on | **Default** | **Default** | Optional add-on |
| `/xgh-whisper` skill + command | If added | **Yes** | **Yes** | If added |
| Context tree output | If added | **Yes** | **Yes** | If added |
| Incremental ingestion (session-start) | If added | **Yes** | **Yes** | If added |
| PR thread extraction (P1) | | **Yes** | **Yes** | |
| Convention detection (P1) | | **Yes** | **Yes** | |
| Git blame / hot-zone analysis (P1) | | | **Yes** | |
| Review assist (P2) | | | **Yes** | |
| Cross-repo learning (P2) | | | **Yes** | |

**Auto-selection:** Based on archetype chosen during `/xgh-init`:
- Solo Dev: Not installed by default. Available via `xgh plugin add whisperer`.
- OSS Contributor: Installed by default (the killer use case for onboarding).
- Enterprise: Installed by default with full feature set.
- OpenClaw: Not installed by default. Available via `xgh plugin add whisperer`.

---

## 6. Hooks & Skills Integration

### 6.1 Existing Hooks -- Full Integration Map

xgh ships 4 hooks today. Here is every hook, what it does, and exactly how Repo Whisperer interacts with it.

#### Hook 1: `xgh-session-start.sh` (SessionStart)

**What it does today:** Loads top 5 context tree files by importance/maturity score, injects the decision table (Cipher memory search reminders), and optionally triggers `/xgh-brief` when `XGH_BRIEFING=1`.

**Whisperer integration: EXTENDED**

Repo Whisperer adds an incremental ingestion check after context tree loading:

1. After existing context tree load, read `.xgh/whisperer/state.yaml`.
2. Compare `branches.<current>.last_ingested_hash` with current `git log -1 --format=%H`.
3. If new commits exist, spawn incremental ingestion in the background (non-blocking, <500ms budget).
4. Append a `"whispererStatus"` key to the JSON output:
   - `"whispererStatus": "up-to-date"` -- no new commits since last ingestion.
   - `"whispererStatus": "ingesting"` -- new commits detected, background ingestion started.
   - `"whispererStatus": "not-bootstrapped"` -- no state file exists, suggest `/xgh-whisper --bootstrap`.
5. Context tree files from `repo-history/decisions/` and `repo-history/conventions/` are already loaded by the existing scoring logic -- no special handling needed.

**Why extend, not consume:** The session-start hook is the natural trigger for incremental ingestion. Whisperer adds one git comparison and one background spawn -- well within the hook's performance budget.

#### Hook 2: `xgh-prompt-submit.sh` (UserPromptSubmit)

**What it does today:** Detects code-change intent via regex (implement, refactor, fix, build, etc.), injects Cipher tool hints.

**Whisperer integration: EXTENDED**

Whisperer adds a "check history first" nudge when the agent is about to modify files with historical significance:

1. When `promptIntent == "code-change"`, check if the prompt references specific files or modules.
2. Look up those file paths in `.xgh/whisperer/state.yaml` or Cipher metadata for known constraints, decisions, or high change frequency.
3. If history exists, inject an additional tool hint:
   - `"whisperHint": "cipher_memory_search with filter type:repo-whisperer for file paths mentioned in the prompt"`.
4. If the file is in a known "hot zone" (high change frequency), add:
   - `"whisperWarning": "This file has high change frequency (N changes in last quarter). Check constraints before modifying."`.

**Why extend, not replace:** The existing intent detection is reused. Whisperer adds a conditional check that fires only when code-change intent is detected AND file-level history data exists. Zero overhead when Whisperer has no data for the relevant files.

#### Hook 3: `cipher-pre-hook.sh` (PreToolUse)

**What it does today:** Detects when the agent sends complex/structured content to Cipher's 3B extraction model and warns that extraction will likely fail. Suggests direct Qdrant storage as an alternative.

**Whisperer integration: CONSUMED (no changes)**

Repo Whisperer benefits from this hook indirectly. When Whisperer stores classified chunks via `cipher_store_reasoning_memory`, the chunks may contain structured content (markdown tables, code snippets from PR descriptions). The pre-hook's warning ensures the agent switches to direct Qdrant storage for complex Whisperer content, preventing silent data loss.

**No changes required.** The hook already handles the exact failure mode Whisperer's storage pipeline would encounter.

#### Hook 4: `cipher-post-hook.sh` (PostToolUse)

**What it does today:** Detects when Cipher extraction returns `extracted: 0` (the 3B model filtered content) and instructs the agent to retry via direct Qdrant storage using `qdrant-store.js`.

**Whisperer integration: CONSUMED (no changes)**

Same indirect benefit as the pre-hook. If a Whisperer chunk fails to store via Cipher's extraction pipeline, the post-hook catches the failure and triggers a direct Qdrant write. This ensures Whisperer's classified chunks always persist, even when they contain complex content that Cipher's 3B model rejects.

**No changes required.** The existing retry mechanism covers Whisperer's storage needs.

### 6.2 Existing Skills -- Integration Map

| Skill | Whisperer Role | How |
|-------|---------------|-----|
| **`/xgh-brief`** | **Consumed by.** | When `/xgh-brief` generates a session briefing, it can include a "Repository Context" section sourced from Whisperer's latest ingestion: "12 new commits on main since your last session. 2 decisions detected. 1 affects your current branch." This is additive -- `/xgh-brief` pulls from Whisperer memory the same way it pulls from Slack or Jira. |
| **`/xgh-ask`** | **Extended.** | Gains a `--history` flag (RW-P1-05) that biases `cipher_memory_search` toward `type: repo-whisperer` memories. Without the flag, `/xgh-ask` queries all memory types as usual. Whisperer results include source attribution (commit hash, PR number) that standard `/xgh-ask` results do not have. |
| **`/xgh-curate`** | **Triggered by.** | When Whisperer writes a `maturity: draft` decision to the context tree, a developer or agent reviewing the context tree can use `/xgh-curate` to promote it to `maturity: validated` or `maturity: core`. This is the quality gate: Whisperer proposes, humans validate via curate. |
| **`/xgh-status`** | **Extended.** | `/xgh-status` gains a Whisperer section: last ingestion date, commits ingested, chunks stored, decisions found, conventions detected, state file health. Shows `"not-bootstrapped"` if no ingestion has occurred. |
| **`/xgh-index`** | **Complementary.** | `/xgh-index` indexes the current codebase structure (architecture, modules, dependencies). Whisperer indexes the codebase history (decisions, evolution, constraints). They are complementary: index tells you what the code IS, Whisperer tells you how it GOT there. No direct integration needed -- they write to different Cipher metadata types. |
| **`/xgh-investigate`** | **Consumed by.** | When investigating a bug, `/xgh-investigate` can query Whisperer memory for past incidents affecting the same files: "This file was last reverted in PR #445 for a similar error. The root cause was a race condition in the connection pool." Whisperer's `bug-fix-rationale` and `revert-reason` classifications are directly relevant to investigation workflows. |
| **`/xgh-help`** | **Extended.** | `/xgh-help` adds Whisperer commands to its output: `/xgh-whisper --bootstrap`, `/xgh-whisper --pr <N>`, `/xgh-whisper <path>`, `/xgh-ask --history`. Includes a "Getting Started" section for repos that have not been bootstrapped. |

### 6.3 New Components Introduced

| Component | Type | Path | Purpose |
|-----------|------|------|---------|
| **`/xgh-whisper` skill** | Skill | `skills/whisperer/whisperer.md` | Main entry point. Handles `--bootstrap`, `--pr <N>`, `--file <path>`, and bare invocation. Orchestrates the three-layer pipeline. |
| **`/xgh-whisper` command** | Command | `commands/whisper.md` | Slash command that triggers the `xgh:whisperer` skill. |
| **Whisperer config** | Config | `.xgh/config.yaml` -> `modules.whisperer` | Module-level configuration: ingestion depth, branch filters, file exclusions, classification thresholds. |

**No new hooks are introduced.** Whisperer extends two existing hooks (`session-start.sh` and `prompt-submit.sh`) rather than adding new hook files. This keeps the hook surface minimal.

---

## 7. Non-Goals

Repo Whisperer is a historical context layer. These are things it explicitly does NOT do:

| Non-Goal | Why Not | Related Feature |
|----------|---------|-----------------|
| **Real-time git monitoring** | Whisperer ingests at session boundaries (session-start) and on demand. It does not watch for new commits in real time. Background daemons add complexity and resource usage. | Session-start incremental mode is sufficient. |
| **Code generation or modification** | Whisperer surfaces context. It never generates code, writes commits, or creates PRs. It informs decisions, it does not make them. | Agent's own coding capabilities. |
| **Git workflow management** | Whisperer does not manage branches, resolve merge conflicts, or enforce branching strategies. It reads git, never writes to it. | Developer's git workflow. |
| **Full conversation replay** | Whisperer stores classified summaries of PR discussions, not verbatim transcripts. Full replay is a different feature (Session Replay). | Session Replay proposal. |
| **Ticket/issue management** | Whisperer can detect linked issue references (e.g., "PAYMENTS-2341") but does not create, update, or manage tickets. | Jira MCP, `/xgh-implement`. |
| **Security scanning** | Whisperer does not audit git history for secrets, vulnerabilities, or compliance issues. It is a context tool, not a security tool. | `git-secrets`, `trufflehog`, dedicated security scanners. |
| **Build/CI integration** | Whisperer does not read CI logs, build artifacts, or test results. It operates purely on git history and PR discussions. | External CI/CD tooling. |
| **Replacing commit message conventions** | Whisperer works better with good commit messages but does not enforce or rewrite them. It takes what exists and extracts maximum value. | Conventional Commits, commitlint. |

**What Whisperer enables but does not implement:**

- **Change Impact Prediction** (P2) -- Whisperer's data is the foundation. A future feature analyzes the patterns.
- **Onboarding Autopilot** (P2) -- Whisperer provides the content. A guided tour skill consumes it.
- **Cross-Repo Learning** (P2) -- Whisperer stores per-repo. Linked workspaces connect the dots.

---

## 8. Open Questions

### 8.1 Design Decisions Needing Input

| # | Question | Options | Recommendation | Needs |
|---|----------|---------|---------------|-------|
| Q1 | **How should the LLM classify chunks in bootstrap mode?** 500 commits means ~500 LLM calls for classification. This is slow and expensive. | (a) Use LLM for all classification (accurate, slow). (b) Use regex/heuristic for initial pass, LLM only for ambiguous cases (fast, less accurate). (c) Batch classification -- send 10-20 commits per LLM call with structured output. | **(c)** -- Batch classification. Batching amortizes LLM overhead while maintaining accuracy. The classifier prompt can handle 10-20 commits per call with a structured JSON output schema. | Prototype: benchmark batch sizes of 5, 10, 20 for accuracy vs. speed tradeoff. |
| Q2 | **Should Whisperer use the same Cipher collection or a separate one?** | (a) Same collection as all xgh memories, distinguished by `type: repo-whisperer` metadata tag. (b) Separate Qdrant collection `{team}-whisperer`. | **(a)** -- Same collection with metadata tagging. Cipher already supports metadata filtering. A separate collection adds operational complexity (backup, migration) and prevents cross-type semantic queries ("find anything related to the auth module" spanning both curated knowledge and git history). | Confirm Qdrant metadata filter performance with 10K+ vectors in a single collection. |
| Q3 | **How should incremental ingestion handle rebased/force-pushed branches?** | (a) Detect force-push (tracked hash not in ancestry of current HEAD) and re-ingest from the fork point. (b) Detect force-push and skip -- manual `/xgh-whisper --bootstrap` required. (c) Always ingest new commits regardless of ancestry. | **(a)** -- Detect and re-ingest from fork point. Force-pushes are common in PR workflows (rebase before merge). Silent data staleness from option (b) would erode trust. Option (c) risks duplicate chunks from rebased commits. | Test with common rebase scenarios: squash-and-merge, interactive rebase, `--force-with-lease`. |
| Q4 | **What is the minimum git history depth that provides value?** | (a) 50 commits (last week or two). (b) 500 commits (default, ~3-6 months). (c) Full history (all commits ever). | **(b)** -- 500 commits as the default. 50 is too shallow for meaningful convention detection. Full history is slow and includes ancient decisions that may no longer apply. 500 hits the sweet spot of "recent enough to be relevant, deep enough to capture patterns." Power users can override with `--depth`. | User testing: does 500 feel "enough"? Track queries that hit the depth boundary and return no results. |
| Q5 | **Should context tree entries from Whisperer be auto-committed?** | (a) Auto-commit in a dedicated branch (`xgh/whisperer-updates`) for PR review. (b) Stage but do not commit -- developer commits manually. (c) Write to working tree, let normal git flow handle it. | **(c)** -- Write to working tree. Auto-committing or auto-branching adds git complexity that many developers would find surprising. Writing to the working tree means the developer sees new context tree files in `git status` and can review, commit, or discard them naturally. | Confirm developers are comfortable with Whisperer files appearing in their `git status`. |

### 8.2 Technical Unknowns

| # | Unknown | Risk Level | Investigation Plan |
|---|---------|-----------|-------------------|
| T1 | **Classification accuracy with heuristics vs. LLM.** Can regex/heuristic patterns reliably distinguish `decision` from `context-note`? | High | Build a labeled dataset of 200 commits (manually classified). Benchmark heuristic-only vs. LLM-only vs. hybrid. Target: >85% agreement with human labels. |
| T2 | **Cipher query performance with large Whisperer datasets.** 500 commits produce ~1000-2000 chunks. Combined with existing Cipher data, does search stay under 1s? | Medium | Benchmark `cipher_memory_search` with metadata filter `type: repo-whisperer` on a collection with 5K, 10K, 20K vectors. Measure P50 and P99 latency. |
| T3 | **Background ingestion reliability on session-start.** Spawning a background process from a hook -- does it survive if the parent hook exits? Does it conflict with the agent's work? | Medium | Test background process lifecycle: hook exits -> background process continues -> Cipher writes complete. Test concurrent access: background ingestion writing to Cipher while agent queries Cipher. |
| T4 | **PR thread API rate limits.** GitHub API rate limit is 5000 req/hr for authenticated users. A bootstrap with PR extraction could hit this. | Medium | Calculate worst-case: 500 commits -> ~100 unique PRs -> ~300 API calls (PR + comments + reviews). Well under 5000/hr. Monitor with `X-RateLimit-Remaining` header. |
| T5 | **Handling of very large repositories.** Repos with 50K+ commits -- does the depth default of 500 provide enough value? Does the state file grow unmanageably? | Low | State file tracks per-branch HEAD only -- O(branches), not O(commits). For very large repos, test with depth 1000 and 2000. Measure ingestion time scaling. |

### 8.3 Scope Boundary Questions

| # | Question | Current Answer | May Change If |
|---|----------|---------------|---------------|
| S1 | Does Repo Whisperer replace manual context tree curation? | **No.** It proposes context tree entries (as `maturity: draft`). Humans validate and promote via `/xgh-curate`. Automated extraction complements, not replaces, intentional curation. | Classification accuracy exceeds 95% -- then auto-promotion to `validated` could be considered. |
| S2 | Should Whisperer work without Cipher? | **No.** Cipher (Qdrant vectors) is the primary storage and retrieval engine. Context tree files are a secondary output for high-confidence entries. Without Cipher, Whisperer cannot perform semantic search over history. | A lightweight local SQLite mode could be explored for Solo Dev archetype, but is not in scope. |
| S3 | Is Momentum a prerequisite for Whisperer? | **No.** They are independent features. Momentum captures session-level state. Whisperer captures repository-level history. They complement each other: Momentum knows "where you left off," Whisperer knows "why the code is like this." | If both ship, the session-start hook gains both Momentum briefing and Whisperer status -- the hook orchestrates both independently. |
| S4 | Does Whisperer interact with the ingest pipeline? | **Not in P0/P1.** Ingest handles external sources (Slack, Jira). Whisperer handles internal sources (git, PRs). They write to the same Cipher collection with different metadata types. | P2: Whisperer could correlate git decisions with Jira tickets referenced in commit messages, creating cross-source links. |

---

## Appendix A: Implementation Sequence

Suggested implementation order, mapping to existing xgh development patterns:

| Phase | Scope | Components | Est. Effort |
|-------|-------|-----------|-------------|
| **Phase 1** | P0 Core (extractors + storage) | `git-log-extractor`, `diff-hunk-extractor`, chunker/classifier (heuristic mode), Cipher storage with metadata, dedup layer, `state.yaml` schema, `.xgh/whisperer/` directory | 3-4 days |
| **Phase 2** | P0 Surface (skill + hooks + context tree) | `skills/whisperer/whisperer.md`, `commands/whisper.md`, `session-start.sh` extension (incremental mode), `prompt-submit.sh` extension (history hints), context tree output, config schema, `techpack.yaml` registration | 2-3 days |
| **Phase 3** | P0 Polish (bootstrap + edge cases) | Bootstrap mode with progress, targeted mode, graceful degradation, error handling, tests | 2-3 days |
| **Phase 4** | P1 Enhanced (PR threads + intelligence) | PR thread extractor (GitHub MCP), Decision Extractor, `/xgh-ask --history`, convention detection, revert intelligence, git blame integration | 4-5 days |
| **Phase 5** | P2 Extended (cross-cutting features) | Change impact prediction, onboarding autopilot, cross-repo learning, review assist, velocity analytics | Deferred until archetype system ships |

**Total estimated effort:** 11-15 days for P0+P1. P2 is deferred.

---

## Appendix B: Classification Taxonomy

The chunker/classifier assigns each extracted chunk one of these classifications:

| Classification | Definition | Signal Patterns | Example |
|---------------|-----------|-----------------|---------|
| `decision` | A deliberate choice between alternatives | "chose X over Y", "decided to", "after discussion", approval signals in PR | "Chose RS256 over HS256 for JWT signing" |
| `tradeoff` | An acknowledged compromise | "tradeoff", "at the cost of", "we accept", "good enough" | "O(n^2) is acceptable because n < 10" |
| `constraint` | A hard boundary that must not be violated | "must", "do not change without", "required by", "blocked by" | "Mobile client validates tokens locally" |
| `convention` | A team pattern or standard | "always use", "prefer", "our convention", repeated review feedback | "Use exhaustive switch statements" |
| `bug-fix-rationale` | Why a bug existed and how it was fixed | "root cause", "the bug was", "fixed by", linked issue references | "Race condition in connection pool caused intermittent 500s" |
| `revert-reason` | Why a change was rolled back | "Revert", "reverted because", "broke", "regression" | "Reverted new caching: caused stale data in multi-tenant mode" |
| `refactor-motivation` | Why code was restructured | "refactor", "extracted", "simplified", "tech debt" | "Extracted payment logic into service layer for testability" |
| `context-note` | General context that does not fit other categories | Everything else with substantive content | "Updated dependencies to latest patch versions" |

**Confidence scoring:** Each classification includes a `confidence_score` (0.0-1.0). Scores below `classification_threshold` (default 0.6) are downgraded to `context-note`. Scores above `context_tree_threshold` (default 0.8) are eligible for context tree output.

---

## Self-Review

**Engineer lens:**
- Fixed: Added explicit performance budget for background ingestion on session-start, including the non-blocking constraint.
- Fixed: Clarified that deduplication tracks per-branch HEAD, not a global position, to handle multi-branch workflows.
- Fixed: Added handling for squash-merged PRs in edge cases (P0 uses squash commit message, P1 recovers full discussion via API).
- Fixed: Specified that context tree files use `maturity: draft` (not `validated`) so human review via `/xgh-curate` is the quality gate.

**PM lens:**
- Fixed: Added quantified impact table with annual cost per developer (52 hours/year) to match Momentum PRD's rigor.
- Fixed: Strengthened the OSS Contributor persona -- this is the "killer use case" and the story now emphasizes maintainer frustration reduction alongside contributor benefit.
- Fixed: Added "What Whisperer enables but does not implement" section to Non-Goals for forward-looking clarity.

**Designer lens:**
- Fixed: Ensured all example outputs use consistent visual style (tables, blockquotes, classification badges) matching the xgh output convention.
- Fixed: Added progressive disclosure principle -- summary first, `--detail` flag for full narrative.
- Fixed: Added `🤖` hint pattern in bootstrap output to teach users discovery patterns ("Try asking...").

*This PRD is a living document. Update it as design decisions from Section 8 are resolved.*
