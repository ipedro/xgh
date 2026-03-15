# Deja Vu — Product Requirements Document

**Feature:** Deja Vu (pattern-matched preemptive warnings for xgh)
**Author:** Pedro (via Claude Code)
**Date:** 2026-03-15
**Status:** PRD — ready for engineering review
**Proposal Source:** [`intelligence-layer.md`](./intelligence-layer.md)

---

## 1. Overview

### 1.1 Problem Statement: The Trigger Gap

Memory systems are pull-based. They store knowledge faithfully but require someone — human or agent — to ask the right question at the right moment. The most dangerous knowledge gaps are not the ones you are aware of; they are the ones where you do not even realize a question should be asked.

**Quantified impact:**

| Metric | Value | Source |
|--------|-------|--------|
| Average time to discover a past failure applies to current work | 2-6 hours (post-implementation) | Developer self-report; code review feedback cycles |
| Percentage of reverted PRs caused by repeating known-bad approaches | ~15-25% | Estimate from revert frequency in mid-size teams |
| Past decisions/failures stored in memory but never retrieved proactively | >80% | Pull-based systems only serve explicit queries |
| Time spent re-debugging a previously encountered issue | 1-4 hours per recurrence | Same issue, different engineer, no institutional transfer |
| Average cost of a repeated architectural mistake (reverted branch + re-implementation) | 1-3 developer-days | Branch lifespan analysis on reverted PRs |
| Knowledge transfer meetings per quarter (to prevent repeat mistakes) | 4-8 per team | Calendar analysis; retrospectives, post-mortems, knowledge shares |

The irony: xgh's Cipher memory and context tree already contain the failure patterns, abandoned approaches, and decision records that would prevent these mistakes. Nothing connects them to the moment of action. **Deja Vu solves the trigger problem.**

### 1.2 Vision

With Deja Vu, every past failure becomes a tripwire protecting the next person. The agent is intercepted *before* it repeats a known-bad approach — not after. Failed experiments become organizational antibodies. The team gets smarter not just from what it builds, but from what it tried and discarded.

**Before Deja Vu:**
```
Agent starts implementing approach → Works for hours → Hits known failure →
Searches memory after the fact → Finds the warning → Reverts → Starts over (hours lost)
```

**After Deja Vu:**
```
Agent starts implementing approach → Deja Vu intercepts via hook → Warning surfaces in <1s →
Agent reads decision record → Pivots immediately → No time wasted
```

### 1.3 Success Metrics

| Metric | Current Baseline | Target | Measurement Method |
|--------|-----------------|--------|-------------------|
| Repeated failure rate (same pattern causing reverts) | ~15-25% of reverts | <5% of reverts | Track revert reasons against Deja Vu pattern library |
| Warning-to-action ratio (warnings that change behavior) | N/A | >60% | Agent heeds warning vs. dismisses and proceeds |
| False positive rate (warnings dismissed as irrelevant) | N/A | <15% | Feedback loop: dismissed warnings / total warnings |
| Warning latency (time from signal to warning) | N/A | <500ms (fast mode), <2s (rich mode) | Wall-clock time from hook trigger to warning render |
| Pattern library growth (new patterns captured per week) | N/A | 3-5 per active project | Count of `deja_vu_pattern` entries created per week |
| Time saved per intercepted failure (estimated) | 0 | 2-4 hours per interception | Pre/post comparison of similar task durations |
| Developer trust score (weekly pulse) | N/A | >4/5 | Optional one-question survey: "Were Deja Vu warnings useful this week?" |

---

## 2. User Personas & Stories

### 2.1 Solo Dev — "The Forgotten Lesson"

**Persona:** Alex, a developer who works on personal projects in evenings and weekends. No team, no one to remind them of past mistakes.

**Before:** Alex starts adding Redis caching to their API. Six months ago, they tried the same thing and abandoned it after connection pool exhaustion crashed the service under load. The reasoning chain sits in Cipher. But Alex forgot about it entirely — why would they search for "Redis connection pool failures" when they are confidently setting up caching?

**Story:** As a solo developer, I want my AI agent to automatically warn me when my current approach matches something I tried and abandoned before — even if I have completely forgotten about it — so that I never repeat my own mistakes.

**After:** Alex tells the agent to add Redis caching. The `UserPromptSubmit` hook fires. Deja Vu extracts signals ("redis", "cache", "user-service"), queries Cipher, and finds the match:

```markdown
## 🐴🤖 Deja Vu Warning

**Pattern match (0.82 confidence)** — this approach was tried before.

| | |
|---|---|
| **When** | 2025-09-14 (6 months ago) |
| **What happened** | Redis caching for this service was reverted after connection pool exhaustion under >200 concurrent users |
| **Resolution** | Switched to in-memory LRU cache with TTL — sufficient for the use case |
| **Decision record** | `context-tree://architecture/caching-strategy.md` |

**Options:**
1. Read the decision record before proceeding
2. Dismiss this warning (I understand the risk)
3. Mark this pattern as resolved (circumstances have changed)
```

Alex reads the decision record, confirms the constraint still exists, and uses the LRU approach. Saved themselves a day of debugging.

**Delight factor:** The realization that your past self left tripwires for your future self — without any extra effort.

---

### 2.2 OSS Contributor — "The Newcomer Shield"

**Persona:** Jordan, a new contributor to an open-source project. Enthusiastic, competent, but without institutional knowledge of the project's history.

**Before:** Jordan opens a PR refactoring the authentication middleware to make it "cleaner." The current implementation is deliberately ugly because it handles a subtle race condition documented in a decision record. Jordan does not know the decision record exists, so they never search for it. A maintainer catches it in review — after Jordan spent an afternoon on the refactor.

**Story:** As an open-source contributor, I want the AI agent to warn me when my changes touch areas with documented gotchas or past failures, so that I do not waste time on approaches the project has already tried and rejected.

**After:** Jordan tells the agent to refactor the auth middleware. Deja Vu intercepts at `UserPromptSubmit`:

```markdown
## 🐴🤖 Deja Vu Warning

**Pattern match (0.88 confidence)** — documented constraint in this area.

| | |
|---|---|
| **Area** | `src/middleware/auth/` |
| **Constraint** | Current implementation handles a race condition with concurrent token refresh. Previous refactor attempt (issue #247) was reverted. |
| **Severity** | High — regression risk |
| **Decision record** | `context-tree://architecture/auth-middleware-race-condition.md` |

**Options:**
1. Read the decision record before proceeding
2. Dismiss this warning (I understand the risk)
3. Mark this pattern as resolved (circumstances have changed)
```

Jordan reads the decision record, understands the race condition, and either preserves the critical logic or finds a cleaner way that still handles it. The maintainer does not have to catch this in review.

**Delight factor:** Institutional knowledge transferred to a newcomer in seconds, without a single meeting or Slack message.

---

### 2.3 Enterprise — "The Cross-Team Immune System"

**Persona:** Priya, a senior engineer on Team B. Team A tried adopting a new API pattern last quarter and abandoned it after integration test flakiness. The knowledge lives in Team A's Cipher workspace.

**Before:** Priya's team independently decides to adopt the same API pattern. They spend a sprint implementing it before discovering the same flakiness. Team A and Team B never talked about it — "why would we check what Team A's microservice team did when we're building a data pipeline?"

**Story:** As an enterprise engineer, I want Deja Vu to surface failure patterns from other teams in my organization, so that Team B learns from Team A's mistakes without requiring cross-team meetings or coordination overhead.

**After:** With linked workspaces enabled, Deja Vu queries cross-project patterns. When Priya's agent starts implementing the API pattern:

```markdown
## 🐴🤖 Deja Vu Warning

**Cross-project pattern match (0.79 confidence)** — similar approach failed in another project.

| | |
|---|---|
| **Source project** | `team-a/order-service` |
| **When** | 2025-12-20 (3 months ago) |
| **What happened** | GraphQL federation pattern caused intermittent 5s timeouts in integration tests due to schema stitching latency |
| **Resolution** | Reverted to REST with OpenAPI spec generation |
| **Contact** | Team A's `#order-service` channel |

**Options:**
1. Read the full failure report
2. Dismiss this warning (our context is different)
3. Mark this pattern as resolved (the underlying issue was fixed)
```

Priya investigates, finds the root cause was in the schema stitching library (now patched), proceeds with awareness, and avoids the specific configuration that caused the flakiness. One warning saved a sprint.

**Delight factor:** Cross-team knowledge sharing that happens automatically, without coordination overhead. Teams build organizational immunity.

---

### 2.4 OpenClaw — "The Personal Coach"

**Persona:** Sam, who uses xgh as a personal AI assistant. Learning new technologies, setting up infrastructure for personal projects.

**Before:** Sam starts setting up a Kubernetes cluster for a hobby project. Last time they did this (4 months ago), they spent 4 hours fighting RBAC configuration before finding the right pattern. That learning is in Cipher, but Sam does not think to search for "Kubernetes RBAC setup" — they are focused on the cluster, not RBAC specifically.

**Story:** As an OpenClaw user, I want Deja Vu to recognize when I am about to encounter a challenge I have solved before and proactively surface the solution, turning my personal history into personal coaching.

**After:** Sam mentions setting up a Kubernetes cluster. Deja Vu catches the signal:

```markdown
## 🐴🤖 Deja Vu Warning

**Pattern match (0.74 confidence)** — you solved this challenge before.

| | |
|---|---|
| **When** | 2025-11-08 (4 months ago) |
| **Challenge** | Kubernetes RBAC configuration took 4 hours to resolve |
| **Solution** | Used `ClusterRoleBinding` with `system:serviceaccount` prefix pattern |
| **Your note** | "The docs are misleading — you need the full service account path, not just the name" |

**Options:**
1. Apply the pattern from last time
2. Dismiss (I want to try a different approach)
```

Sam applies the pattern immediately. Four hours compressed into four seconds.

**Delight factor:** The AI becomes a personal tutor that remembers every lesson you have ever learned.

---

## 3. Requirements

### 3.1 Must Have (P0) — Core Warning Pipeline

These requirements form the minimum viable Deja Vu. Without all of them, the feature does not deliver its core promise.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **DV-P0-01** | **Signal extraction at prompt submit:** The `UserPromptSubmit` hook extracts lightweight signals (3-5 terms) from the developer's prompt — action type, target area, technology/library names, architectural pattern keywords. | Signal extraction adds <50ms to hook execution. Extracts: action signals (implement, refactor, migrate), context signals (file paths, branch names), approach signals (technology names, pattern names). |
| **DV-P0-02** | **Pattern matching via Cipher query:** Extracted signals are used to query a dedicated Deja Vu collection in Cipher using hybrid search (semantic similarity + BM25 keyword match on file paths, library names, pattern identifiers). | Query completes in <300ms. Returns matches with confidence scores. Configurable confidence threshold (default: 0.75). Only matches above threshold proceed to warning composition. |
| **DV-P0-03** | **Warning composition (fast mode):** For matches above threshold, compose a template-based warning using stored pattern data. No LLM call. Warning includes: when the pattern was recorded, what happened, the outcome, the resolution, and a link to the decision record. | Warning renders in <100ms from pattern match data. Uses the `🐴🤖 Deja Vu Warning` header. Includes confidence score, structured table, and options (read record, dismiss, mark resolved). |
| **DV-P0-04** | **Warning injection via hook output:** The composed warning is injected into the hook response as `additionalContext`, appearing in the agent's context as a system-level advisory before the agent acts on the prompt. | Warning appears in agent context before any code generation or tool calls. Uses the same `hookSpecificOutput` → `additionalContext` mechanism as existing Cipher hooks. |
| **DV-P0-05** | **Pattern storage format:** Deja Vu introduces a `deja_vu_pattern` memory type stored in Cipher. Schema includes: `id`, `signals[]`, `area`, `outcome`, `severity`, `reason`, `original_session`, `ticket`, `related_decisions[]`. | Patterns stored with consistent schema. Queryable by signal terms, area, and outcome. Schema version field for forward compatibility. |
| **DV-P0-06** | **Automatic pattern extraction from reverts:** During the post-session curation step (`cipher_extract_and_operate_memory`), when an agent reverts code, abandons an approach, or records a "this didn't work" outcome, the system extracts it as a `deja_vu_pattern`. | No manual pattern creation required. Patterns are extracted from existing post-session flows. Agent instruction includes explicit guidance to tag abandoned/reverted work. |
| **DV-P0-07** | **Confidence threshold configuration:** Configurable minimum confidence threshold for firing warnings. Default: 0.75. Stored in `.xgh/config.yaml` under `modules.deja-vu.confidence-threshold`. | Threshold adjustable per-project. Values below threshold are silently discarded. Setting threshold to 1.0 effectively disables warnings without removing the module. |
| **DV-P0-08** | **Warning dismiss/accept flow:** When the agent presents a Deja Vu warning, the developer can: (1) read the linked decision record, (2) dismiss the warning and proceed, (3) mark the pattern as resolved. Each action feeds back into the confidence calibration. | Dismiss decreases pattern confidence for that signal combination by a configurable decay factor (default: 0.1). Accept (read + change approach) holds confidence. Mark-resolved adds a `resolved_at` timestamp and stops the pattern from firing. |
| **DV-P0-09** | **Temporal decay:** Pattern match confidence decays over time. Configurable half-life (default: 180 days / 6 months). A failure from last week is highly relevant; one from two years ago is less so. | Decay applied at query time, not at storage time (patterns are never modified by decay). Formula: `effective_confidence = raw_confidence * 0.5^(days_since_pattern / half_life)`. Configurable via `modules.deja-vu.decay-half-life`. |
| **DV-P0-10** | **Specificity threshold:** Generic matches ("you used Redis before") are suppressed. Only specific matches with multiple correlated signals fire warnings. | Minimum 2 correlated signals required for a warning to fire. Single-signal matches are logged but not surfaced. Prevents warning fatigue from broad, unhelpful matches. |
| **DV-P0-11** | **Module manifest and techpack registration:** Deja Vu ships as a module with `module.yaml` manifest. Components registered in `techpack.yaml`: hook, skill, command, config. | New component IDs: `deja-vu-prompt-hook`, `deja-vu-post-session-hook`, `deja-vu-skill`, `deja-vu-command`. Components follow existing schema patterns. Module manifest declares dependencies: `xgh >= 1.0.0`, `cipher: true`, `context-tree: true`. |
| **DV-P0-12** | **Disable with one line:** `deja-vu: { enabled: false }` in `.xgh/config.yaml` turns all hooks into no-ops. Zero performance impact when disabled. | Hooks check the `enabled` flag first and exit 0 immediately if disabled. No Cipher queries, no signal extraction, no warnings. |
| **DV-P0-13** | **`/xgh-deja-vu` skill and command:** Skill file `skills/deja-vu/deja-vu.md` and command `commands/deja-vu.md` for manually querying pattern history, viewing recent warnings, and managing pattern lifecycle (resolve, delete, adjust confidence). | Skill supports: `--recent` (last 10 warnings), `--patterns` (list all active patterns), `--resolve <id>` (mark pattern resolved), `--stats` (firing rate, false positive rate, pattern count). |

### 3.2 Should Have (P1) — Enhanced Intelligence

These features differentiate Deja Vu from simple keyword matching. They add contextual richness and cross-session learning.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **DV-P1-01** | **Rich mode warnings (LLM-composed):** Opt-in mode that uses the local LLM (already running for Cipher) to synthesize a contextual warning explaining *why this specific situation matches* and *what to do instead*, rather than using a template. | LLM warning composition completes in <2s. Activated via `modules.deja-vu.mode: rich`. Falls back to fast mode if LLM is unavailable. |
| **DV-P1-02** | **PreToolUse interception:** Extend beyond `UserPromptSubmit` to also check at `PreToolUse` — intercepting before specific tool calls (file writes, git operations) that match known failure patterns. | PreToolUse hook extracts signals from tool name + tool input. Same pipeline: signal extraction → Cipher query → warning composition. Adds <100ms to tool call latency when no match found. |
| **DV-P1-03** | **PostToolUse failure detection:** After tool execution, check if the result matches a known failure signature (error patterns, specific exception types, known-bad output patterns). Create new patterns automatically from repeated failures. | PostToolUse hook scans tool results for error patterns. If a failure matches a known pattern, surfaces "This failure was seen before — here is the fix." If a new failure occurs 3+ times, auto-creates a `deja_vu_pattern`. |
| **DV-P1-04** | **Context tree integration for decision records:** When a warning references a decision record in the context tree, Deja Vu includes a 3-line excerpt from the record directly in the warning, so the developer gets immediate context without navigating to another file. | Decision record excerpts pulled from context tree files. Excerpt is first 3 non-empty lines of the document body (after frontmatter). Displayed in the warning under a "From the decision record:" section. |
| **DV-P1-05** | **Warning analytics log:** All fired warnings are logged to `.xgh/deja-vu/warnings.log` with timestamp, pattern ID, confidence, action taken (dismiss/accept/resolve), and outcome. | Log is append-only, rotated at 5MB. Powers the `/xgh-deja-vu --stats` command. Retention: 90 days. |
| **DV-P1-06** | **Cross-project patterns (linked workspaces):** With linked workspaces configured, Deja Vu queries sibling projects' pattern libraries. Cross-project matches are labeled as such and include the source project. | Requires `modules.deja-vu.cross-project: true` and linked workspaces module. Cross-project matches use a higher confidence threshold (+0.05) to reduce noise. Source project and contact channel included in warning. |

### 3.3 Nice to Have (P2) — Future Possibilities

These are features Deja Vu enables but does not implement in v1.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **DV-P2-01** | **Pattern analytics dashboard:** Aggregate Deja Vu firing data to identify systemic issues — which codebase areas generate the most warnings, which patterns keep tripping people up. | `/xgh-deja-vu --dashboard` renders a per-area summary with firing frequency, acceptance rate, and trend arrows. Requires >30 days of warning log data. |
| **DV-P2-02** | **Onboarding accelerator mode:** When a new contributor is detected (first session in a project), Deja Vu lowers its confidence threshold temporarily to surface more institutional knowledge proactively. | Detects new contributor via absence of prior session memories. Temporary threshold reduction: -0.15 for first 5 sessions. Auto-resets to configured threshold. |
| **DV-P2-03** | **Decision deprecation lifecycle:** When a decision record or pattern is no longer relevant (infrastructure changed, library upgraded), mark it deprecated. Deprecated patterns stop firing but remain in the archive for historical analysis. | `--deprecate <id>` flag on the skill command. Deprecated patterns have `deprecated_at` timestamp. Queryable via `--patterns --include-deprecated`. |
| **DV-P2-04** | **Compliance evidence export:** Export Deja Vu warning log as a structured report showing which known risks were surfaced to engineers and what decisions were made. | `--export` flag generates JSON or CSV. Fields: timestamp, pattern, confidence, warning text, action taken, engineer (git username). Suitable for audit review. |
| **DV-P2-05** | **Pattern promotion from Momentum:** When a Momentum session snapshot records a revert or abandoned approach, Deja Vu can auto-promote it to a pattern candidate for review. | Integration with Momentum's session-end capture. Reverted/abandoned tasks flagged for Deja Vu pattern extraction. Developer confirms or discards via `/xgh-deja-vu --pending`. |
| **DV-P2-06** | **Negative knowledge index:** Aggregate all Deja Vu patterns into a "things we tried that didn't work" index, searchable via `/xgh-ask`. A curated anti-pattern library. | Patterns tagged with `type: deja_vu_pattern` already queryable via Cipher. This feature adds a formatted, browsable view via the skill command. |

---

## 4. User Experience

### 4.1 The Warning Moment

This is Deja Vu's core UX. The developer (or their agent) is about to do something that matches a known failure pattern, and Deja Vu intervenes.

**Trigger point:** The warning fires at `UserPromptSubmit` — after the developer types their intent but *before* the agent begins executing it. This is the ideal interception point: the developer has expressed intent, the agent has not yet acted.

**What the developer sees:**

```markdown
## 🐴🤖 Deja Vu Warning

**Pattern match (0.82 confidence)** — this approach was tried before.

| | |
|---|---|
| **When** | 2025-11-20 (4 months ago) |
| **Context** | WebSocket connection management in notification service (ticket NOTIF-334) |
| **Outcome** | Reverted — AWS ALB silently drops WebSocket connections after 60s idle timeout |
| **Resolution** | Team switched to Server-Sent Events (SSE) instead |
| **Decision record** | `architecture/notifications/transport-choice.md` |

> **From the decision record:** "ALB has a hard 60-second idle timeout for WebSocket connections. Keepalive packets are not forwarded. SSE over HTTP/2 maintains the connection via the standard HTTP keepalive mechanism."

**What would you like to do?**
1. 📖 Read the full decision record before proceeding
2. ⏭️ Dismiss — I understand the risk and want to proceed anyway
3. ✅ Mark resolved — circumstances have changed (ALB replaced, timeout configured, etc.)
```

### 4.2 The Dismiss/Accept Flow

When the developer sees a Deja Vu warning, three paths are available:

**Path 1 — Read and pivot (accept):**
The developer reads the decision record, confirms the constraint still applies, and changes their approach. Deja Vu's confidence for this pattern is maintained. The agent proceeds with the alternative approach.

```
Developer: "Good catch. Let's use SSE instead."
Agent: Proceeds with SSE implementation, referencing the decision record for the correct pattern.
```

**Path 2 — Dismiss and proceed:**
The developer reads the warning but decides their context is different (e.g., they migrated off ALB). They dismiss the warning. Deja Vu logs the dismissal and decreases confidence for this specific signal combination by 0.1. If the same pattern is dismissed 3+ times by the same signal combination, it is automatically suppressed for that combination.

```
Developer: "We're on NLB now, not ALB. Dismiss."
Agent: Proceeds with WebSocket implementation. The warning is logged with action: "dismissed", reason: "infrastructure changed".
```

**Path 3 — Mark resolved:**
The developer confirms the underlying issue no longer exists. The pattern is marked `resolved_at: <timestamp>` and stops firing. It remains in the archive for historical queries.

```
Developer: "We migrated to NLB last month. Mark this resolved."
Agent: Pattern updated with resolved status. Future WebSocket work in notification service will not trigger this warning.
```

### 4.3 The Feedback Loop

Every interaction with a Deja Vu warning feeds back into the system:

| Action | Effect on Pattern |
|--------|------------------|
| Read decision record, change approach | Confidence maintained (pattern is useful) |
| Dismiss warning, proceed successfully | Confidence decreased by 0.1 for that signal combination |
| Dismiss warning, later encounter same failure | Confidence increased by 0.15 (pattern was right) |
| Mark resolved | Pattern stops firing; `resolved_at` timestamp recorded |
| Warning fires, developer does not engage | No effect (neutral — developer may not have seen it) |

This creates a self-calibrating system. Useful warnings get reinforced. Stale or irrelevant warnings decay. The pattern library improves with use.

### 4.4 Output Style Guide

Deja Vu warnings follow the xgh output convention: scannable, emoji-accented, table-structured.

**Principles:**
- **Urgent but not alarming:** Warnings are advisory, not blocking. The developer always has the option to proceed.
- **Evidence-based:** Every warning cites specific past events with dates, tickets, and decision records. No vague "this might be a bad idea."
- **Actionable:** Every warning ends with concrete options. The developer knows exactly what to do next.
- **Concise by default:** Fast mode warnings fit in <15 lines. Rich mode adds context but stays under 25 lines.

**Visual elements:**

| Element | Purpose |
|---------|---------|
| `## 🐴🤖 Deja Vu Warning` | Consistent header, immediately recognizable |
| Confidence badge | Transparency: the developer knows how certain the match is |
| Structured table (When / Context / Outcome / Resolution) | Scannable summary of the past event |
| Blockquoted excerpt from decision record | Immediate context without navigating to another file |
| Numbered options with emoji | Clear action paths: read, dismiss, resolve |
| Cross-project label (when applicable) | Indicates the source is another team/project |

### 4.5 Edge Cases

#### No Patterns Exist Yet (Fresh Project)

**Behavior:** Deja Vu has nothing to match against. All hook checks exit silently in <5ms. The developer sees nothing. As the project accumulates session history and the team records failures and decisions, the pattern library grows organically through the post-session curation flow.

**Why not show a "no patterns yet" message?** Because it adds noise. Deja Vu's value comes from its warnings, not from announcing its absence.

#### Multiple Patterns Match the Same Prompt

**Behavior:** If multiple patterns match above threshold, Deja Vu shows them in a single warning block, sorted by confidence (highest first). Maximum 3 warnings per prompt to prevent fatigue. If more than 3 match, the top 3 are shown and a note says "2 additional lower-confidence matches available via `/xgh-deja-vu --recent`."

#### Pattern Matches But Decision Record Is Missing

**Behavior:** If the pattern references a decision record path that no longer exists in the context tree (file deleted, moved, or renamed), the warning still fires but omits the excerpt and decision record link. Instead, it shows: "Decision record not found at original path. The pattern may be outdated — consider reviewing with `/xgh-deja-vu --patterns`."

#### Very Old Patterns (Beyond Decay Threshold)

**Behavior:** Temporal decay naturally suppresses old patterns. A pattern with 0.80 raw confidence and 18-month age (3x the default 6-month half-life) has an effective confidence of `0.80 * 0.5^3 = 0.10` — well below the 0.75 threshold. It will not fire. But it remains queryable via the skill command for historical analysis.

#### High-Frequency Code Areas (Warning Fatigue Risk)

**Behavior:** If a specific code area triggers warnings on >50% of prompts related to it, Deja Vu auto-groups the patterns and shows a single consolidated warning: "This area has 5 documented constraints. Run `/xgh-deja-vu --area src/middleware/auth/` to review them all." This prevents the same file from triggering 5 separate warnings every time someone touches it.

---

## 5. Technical Boundaries

### 5.1 Three-Stage Pipeline

Deja Vu operates as a three-stage pipeline that runs inline with existing hooks:

**Stage 1 — Signal Extraction (hook layer, <50ms)**

Runs inside the `UserPromptSubmit` hook (P0) and optionally `PreToolUse` (P1). Extracts lightweight signals from the agent's current intent:

| Signal Type | Examples | Extraction Method |
|-------------|----------|-------------------|
| **Action signals** | implement, refactor, migrate, add caching, switch framework | Regex + keyword matching on prompt text |
| **Context signals** | File paths, branch names, ticket IDs, module names | Path extraction from prompt + git context |
| **Approach signals** | Technology names, library names, architectural patterns | NLP keyword extraction (Redis, WebSocket, GraphQL, gRPC) |

This stage is deliberately shallow — 3-5 signal terms, not a full semantic analysis. Speed matters because it runs on every prompt.

**Stage 2 — Pattern Matching (Cipher query, <300ms)**

Takes extracted signals and runs a targeted Cipher query against the `deja_vu_pattern` collection:

- **Hybrid search:** Semantic similarity on signal terms + BM25 keyword match on file paths, library names, and pattern identifiers
- **Temporal decay applied at query time:** `effective_confidence = raw_confidence * 0.5^(days / half_life)`
- **Specificity filter:** Minimum 2 correlated signals required
- **Threshold filter:** Only results above configured confidence threshold (default: 0.75) proceed

**Stage 3 — Warning Composition (<100ms fast, <2s rich)**

For matches above threshold, compose the warning:

| Mode | Method | Latency | When to Use |
|------|--------|---------|-------------|
| **Fast** (default) | Template-based. Pulls stored data directly into markdown template. No LLM call. | <100ms | All archetypes by default |
| **Rich** (opt-in) | Local LLM synthesizes contextual explanation of *why this matches* and *what to do instead*. | <2s | Enterprise archetype, opt-in for others |

### 5.2 Performance Budget

| Operation | Budget | Method |
|-----------|--------|--------|
| **Signal extraction (Stage 1)** | <50ms | Regex + keyword extraction in Python (inline in hook) |
| **Pattern matching (Stage 2)** | <300ms | Cipher hybrid query with pre-filtered collection |
| **Warning composition — fast mode (Stage 3)** | <100ms | Template string substitution |
| **Warning composition — rich mode (Stage 3)** | <2000ms | Local LLM call (same instance as Cipher) |
| **Total hook overhead when NO match found** | <100ms | Stage 1 + Stage 2 (early exit) |
| **Total hook overhead when match found (fast)** | <500ms | Stage 1 + Stage 2 + Stage 3 |
| **Pattern extraction at session end** | <200ms | Runs during existing post-session curation (not a new step) |
| **Pattern storage disk usage** | <500B per pattern | YAML/JSON metadata only, no content |

**Non-negotiable:** Deja Vu must NEVER add perceptible latency to prompts that do not trigger a match. The <100ms no-match budget means the developer never notices Deja Vu is running — until it saves them.

### 5.3 False Positive Management

False positives are the death of warning systems. Deja Vu uses four calibration mechanisms:

| Mechanism | How It Works | Effect |
|-----------|-------------|--------|
| **Temporal decay** | Confidence decays with a configurable half-life (default: 6 months). Technologies change; old patterns become less relevant. | Old patterns naturally suppress themselves |
| **Feedback loop** | Dismissals decrease confidence; acceptances maintain it. Repeated dismissals auto-suppress for that signal combination. | Patterns calibrate to actual relevance |
| **Specificity threshold** | Minimum 2 correlated signals required. Single-term matches ("you used Redis") are suppressed. | Prevents vague, unhelpful warnings |
| **Area consolidation** | High-frequency areas auto-consolidate into a single summary warning. | Prevents fatigue in hotspot areas |

**Target false positive rate:** <15%. Measured as: warnings dismissed as irrelevant / total warnings fired. If the rate exceeds 20% for any individual pattern, that pattern is auto-suppressed and flagged for review.

### 5.4 Privacy: What NEVER Gets Stored in Patterns

| Excluded Data | Reason |
|---------------|--------|
| File contents or diffs | Patterns store signal terms and file paths, never code |
| API keys, tokens, credentials | Explicitly excluded from signal extraction |
| Full conversation history | Only the distilled failure reason and resolution |
| Personal identifying information beyond git username | No email, no IP, no device info |
| Contents of `.env` files | Never accessed |

**Privacy contract:** A Deja Vu pattern should be safe to share across teams. It describes *what was tried and why it failed*, not *what the code looks like*.

### 5.5 Memory Structure

Deja Vu reads from existing Cipher memory and context tree but introduces one new memory type:

```yaml
type: deja_vu_pattern
schema_version: 1
id: "dv-2026-03-15-redis-cache-user-service"
signals:
  - "redis"
  - "cache"
  - "user-service"
  - "connection pool"
area: "src/services/user/"
outcome: "reverted"                    # reverted | abandoned | failed | constraint
severity: "high"                       # high | medium | low
reason: "Connection pool exhaustion under >200 concurrent users. Redis Cluster mode required but not configured. Fallback to in-memory LRU cache with TTL was sufficient."
original_session: "2025-12-08"
ticket: "USR-1847"
related_decisions:
  - "context-tree://architecture/caching-strategy.md"
confidence_adjustments:                # Feedback loop history
  - date: "2026-01-15"
    action: "dismissed"
    delta: -0.1
resolved_at: null                      # null = active, ISO date = resolved
deprecated_at: null                    # null = active, ISO date = deprecated
```

### 5.6 Archetype Defaults

| Configuration | Solo Dev | OSS | Enterprise | OpenClaw |
|---------------|----------|-----|------------|----------|
| Enabled | Yes | Yes | Yes | Yes |
| Mode | fast | fast | rich | fast |
| Confidence threshold | 0.75 | 0.75 | 0.70 | 0.75 |
| Decay half-life | 180 days | 365 days | 365 days | 90 days |
| Cross-project | No | No | Yes | No |
| Compliance log | No | No | Yes | No |
| Suppress patterns | `test-*` | `test-*` | None | `test-*` |

**Rationale:** OSS and Enterprise use longer decay because project history is more stable. OpenClaw uses shorter decay because personal projects change faster. Enterprise uses rich mode and a lower threshold to surface more institutional knowledge. Enterprise enables cross-project for organizational learning.

---

## 6. Hooks & Skills Integration

This is Deja Vu's core mechanism. Deja Vu operates entirely through the existing xgh hook and skill system — no new runtime, no new daemon, no new infrastructure.

### 6.1 Hook Integration Map

#### `xgh-session-start.sh` (SessionStart) — **Feeds Deja Vu**

| Aspect | Detail |
|--------|--------|
| **Current behavior** | Loads top 5 context tree files by score, injects decision table, optionally triggers `/xgh-brief` |
| **Deja Vu relationship** | **Feeds.** Session start provides the context signals (branch, project, recent commits) that Deja Vu uses as baseline context for subsequent prompt-level signal extraction. |
| **Modification** | **Minimal extension.** Add a `dejaVuEnabled` boolean to the JSON output so downstream hooks know whether to run the Deja Vu pipeline. Read from `.xgh/config.yaml` → `modules.deja-vu.enabled`. |
| **Why not intercept here?** | Session start is too early — the developer has not expressed intent yet. Deja Vu needs a specific action/approach to match against. Session start provides *context*, not *trigger*. |

**Output change (additive):**
```json
{
  "result": "xgh: session-start loaded 5 context files",
  "contextFiles": [ ... ],
  "decisionTable": [ ... ],
  "briefingTrigger": "off",
  "dejaVuEnabled": true,
  "dejaVuConfig": {
    "confidenceThreshold": 0.75,
    "mode": "fast",
    "decayHalfLife": 180
  }
}
```

---

#### `xgh-prompt-submit.sh` (UserPromptSubmit) — **Primary Interception Point**

| Aspect | Detail |
|--------|--------|
| **Current behavior** | Detects code-change intent via regex, injects Cipher tool hints and decision table |
| **Deja Vu relationship** | **Extended — this is the KEY integration point.** Prompt submit runs *after* the developer types their intent but *before* the agent acts. This is the ideal moment to check for pattern matches. |
| **Modification** | **Major extension.** After existing intent detection, run the Deja Vu three-stage pipeline: signal extraction → Cipher query → warning composition. Append warning (if any) to `additionalContext` alongside existing tool hints. |
| **Why this hook?** | The developer has expressed specific intent ("implement caching with Redis", "refactor the auth middleware"). Deja Vu has something concrete to match against. The agent has not started acting yet, so the warning arrives before any wasted work. |

**Extended flow:**
```
1. Existing: Detect prompt intent (code-change vs. general)
2. Existing: Compose required actions + tool hints
3. NEW: Extract Deja Vu signals from prompt text
4. NEW: If signals found, query Cipher deja_vu_pattern collection
5. NEW: If match above threshold, compose warning
6. NEW: Append warning to output JSON as "dejaVuWarning" key
7. Return combined output
```

**Output change (additive):**
```json
{
  "result": "xgh: prompt-submit decision table injected",
  "promptIntent": "code-change",
  "requiredActions": [ ... ],
  "toolHints": [ ... ],
  "dejaVuWarning": {
    "matched": true,
    "patterns": [
      {
        "id": "dv-2025-12-08-redis-cache",
        "confidence": 0.82,
        "signals_matched": ["redis", "cache", "user-service"],
        "summary": "Redis caching reverted due to connection pool exhaustion",
        "decision_record": "architecture/caching-strategy.md",
        "severity": "high"
      }
    ],
    "renderedWarning": "## 🐴🤖 Deja Vu Warning\n\n..."
  }
}
```

**Performance guard:** If the Deja Vu pipeline exceeds its 500ms budget, it is aborted and the hook returns without a warning. The existing prompt-submit behavior (tool hints, decision table) is never delayed by Deja Vu.

---

#### `cipher-pre-hook.sh` (PreToolUse) — **P1 Extension Point**

| Aspect | Detail |
|--------|--------|
| **Current behavior** | Matches on `cipher_extract_and_operate_memory` and `cipher_workspace_store` tool calls. Warns when sending complex content to Cipher's 3B extraction model. |
| **Deja Vu relationship** | **P1 piggyback.** In P1, Deja Vu adds a second PreToolUse hook that intercepts *all* tool calls (not just Cipher tools) — specifically file writes (`Write`, `Edit`), git operations, and other code-mutating actions. This catches cases where the developer's prompt was generic but the specific tool call reveals the pattern (e.g., prompt says "update the config" but the Edit tool targets `src/middleware/auth/config.ts`). |
| **Modification** | **New parallel hook (P1 only).** Does NOT modify the existing `cipher-pre-hook.sh`. Instead, a new `deja-vu-pre-tool.sh` hook is registered alongside it for the `PreToolUse` event. The existing Cipher pre-hook continues to handle extraction warnings independently. |
| **Why P1 and not P0?** | P0 focuses on prompt-level interception, which catches the majority of cases. PreToolUse interception is a refinement that catches edge cases where the prompt does not reveal the approach but the tool call does. |

**New hook (P1):**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "__HOOKS_DIR__/cipher-pre-hook.sh"
          },
          {
            "type": "command",
            "command": "__HOOKS_DIR__/deja-vu-pre-tool.sh"
          }
        ]
      }
    ]
  }
}
```

---

#### `cipher-post-hook.sh` (PostToolUse) — **P1 Failure Detection**

| Aspect | Detail |
|--------|--------|
| **Current behavior** | Matches on `cipher_extract_and_operate_memory` and `cipher_workspace_store`. Detects `extracted:0` failures and instructs the agent to retry via direct Qdrant storage. |
| **Deja Vu relationship** | **P1 piggyback for failure detection.** A new `deja-vu-post-tool.sh` hook runs alongside the existing cipher post-hook. It checks tool results for error patterns that match known failure signatures in the Deja Vu pattern library. This enables after-the-fact warnings: "This error was seen before — here is the fix." |
| **Modification** | **New parallel hook (P1 only).** Does NOT modify `cipher-post-hook.sh`. Registered as a second PostToolUse handler. Also detects repeated failures (same error 3+ times) and auto-creates `deja_vu_pattern` candidates. |
| **Why P1 and not P0?** | PostToolUse fires *after* something already happened. P0 prioritizes *prevention* (intercept before the mistake). P1 adds *detection* (recognize the failure and help recover faster). |

---

### 6.2 Skills Integration Map

| Skill | Relationship | How Deja Vu Interacts |
|-------|-------------|----------------------|
| **`/xgh-ask`** | **Feeds Deja Vu.** | When a developer asks a question about past failures or decisions, the answer may surface information that should be a Deja Vu pattern. The skill can suggest: "This looks like it should be a Deja Vu pattern. Run `/xgh-deja-vu --create` to add it." |
| **`/xgh-curate`** | **Feeds Deja Vu.** | When the developer curates a decision record (especially one tagged with `alternatives_rejected`), the curate skill can extract signals and create a `deja_vu_pattern` from the rejected alternatives. Each rejected alternative becomes a tripwire. |
| **`/xgh-implement`** | **Intercepted by Deja Vu.** | Implementation prompts are the primary trigger for Deja Vu warnings. When `/xgh-implement` is invoked with a task, the prompt-submit hook fires and Deja Vu checks for patterns matching the implementation approach. If a warning fires, the implement skill should read the decision record before proceeding. |
| **`/xgh-investigate`** | **Feeds Deja Vu.** | Investigation sessions often uncover root causes and failure patterns. When an investigation concludes with a finding, the skill should suggest storing it as a Deja Vu pattern if the finding involves a revert-worthy or constraint-worthy discovery. |
| **`/xgh-brief`** | **Complemented by Deja Vu.** | The briefing skill shows what happened externally (Slack, Jira, GitHub). Deja Vu adds an internal layer: what patterns from the team's history are relevant to today's planned work. A future integration could add a "Deja Vu alerts for today's tickets" section to the briefing. |
| **`/xgh-status`** | **Reports Deja Vu health.** | Status skill adds a Deja Vu section: active pattern count, warnings fired this week, false positive rate, oldest/newest pattern, collection health. |
| **`/xgh-help`** | **Contextual awareness.** | If Deja Vu is enabled, `/xgh-help` includes it in the command reference. If Deja Vu has been firing frequently in a code area, `/xgh-help` may suggest: "This area has documented constraints — run `/xgh-deja-vu --area <path>` to review." |

### 6.3 New Components

| Component | Type | File | Purpose |
|-----------|------|------|---------|
| `deja-vu-prompt-hook` | Hook extension | `hooks/deja-vu-prompt-submit.sh` | Signal extraction + pattern matching inline with existing prompt-submit hook |
| `deja-vu-pre-tool` (P1) | Hook | `hooks/deja-vu-pre-tool.sh` | PreToolUse interception for tool-level pattern matching |
| `deja-vu-post-tool` (P1) | Hook | `hooks/deja-vu-post-tool.sh` | PostToolUse failure detection and auto-pattern creation |
| `deja-vu-skill` | Skill | `skills/deja-vu/deja-vu.md` | Pattern lifecycle management (query, resolve, deprecate, stats) |
| `deja-vu-command` | Command | `commands/deja-vu.md` | `/xgh-deja-vu` slash command |
| `module.yaml` | Manifest | `modules/deja-vu/module.yaml` | Module dependencies and archetype mapping |

---

## 7. Non-Goals

Deja Vu is a pattern-matched warning system. These are things it explicitly does NOT do:

| Non-Goal | Why Not | Related Feature |
|----------|---------|-----------------|
| **Blocking execution** | Deja Vu is advisory. It never prevents the agent from proceeding. The developer always has the final say. Blocking would erode trust. | N/A — by design |
| **Code review or quality analysis** | Deja Vu matches against *past events* (failures, decisions, constraints), not against *code quality rules*. It is not a linter. | Linters, `/xgh-investigate` |
| **Real-time learning during a session** | Deja Vu patterns are created at session end (post-curation), not mid-session. A failure in minute 5 does not become a warning in minute 10 of the same session. | Future: intra-session learning |
| **Automated code changes** | Deja Vu surfaces information. It never modifies code, reverts changes, or applies fixes automatically. | Developer's own workflow, `/xgh-implement` |
| **General knowledge or best practices** | Deja Vu only fires on *your team's specific history*. It does not warn about generic anti-patterns ("don't use `eval`"). | Linters, style guides |
| **Notification or alerting between sessions** | Deja Vu fires during active sessions only. It does not send Slack messages, emails, or push notifications about newly created patterns. | Ingest pipeline notifications |
| **Task management or ticket creation** | Deja Vu surfaces pattern matches but does not create Jira tickets, GitHub issues, or TODO items. | Jira MCP, `/xgh-implement` |
| **Session continuity or state restoration** | Deja Vu is about past failures, not past progress. Session state is Momentum's domain. | Momentum feature |

---

## 8. Open Questions

### 8.1 Design Decisions Needing Input

| # | Question | Options | Recommendation | Needs |
|---|----------|---------|---------------|-------|
| Q1 | **Should Deja Vu extend the existing `prompt-submit.sh` or run as a separate hook?** Claude Code hooks can have multiple handlers per event. | (a) Extend `prompt-submit.sh` with Deja Vu logic inline. (b) Register a separate `deja-vu-prompt-submit.sh` as a second `UserPromptSubmit` handler. | **(b)** — Separate hook. Keeps modules decoupled. The existing hook handles memory tool hints; Deja Vu handles pattern warnings. Each can be enabled/disabled independently. If Deja Vu is disabled, its hook is simply not registered. | Confirm Claude Code supports multiple handlers for the same hook event and that their outputs are merged. |
| Q2 | **How should the Cipher query be scoped?** Deja Vu needs its own collection or tag filter to avoid matching against general memory entries. | (a) Dedicated Qdrant collection `{team}-deja-vu`. (b) Same collection as general memory, filtered by `type: deja_vu_pattern` tag. (c) Separate Cipher workspace. | **(b)** — Same collection with tag filtering. Avoids managing a separate collection. Cipher already supports tag-based filtering. The `type: deja_vu_pattern` tag is sufficient for scoping. | Verify Cipher's tag filtering does not degrade query performance at scale (>1000 patterns). |
| Q3 | **What is the minimum number of patterns needed for Deja Vu to be useful?** The first session has zero patterns. When does Deja Vu start providing value? | (a) Deja Vu is passive until the first pattern exists organically. (b) Deja Vu pre-seeds from the context tree's decision records on first enable. (c) Manual pattern creation via `/xgh-deja-vu --create` for teams that want to bootstrap. | **(b) + (c)** — Pre-seed from context tree AND support manual creation. When Deja Vu is first enabled, scan the context tree for decision records tagged with `alternatives_rejected` and auto-generate pattern candidates. Also allow manual creation for teams migrating institutional knowledge. | Prototype the context-tree scan. How many decision records have `alternatives_rejected` tags in a typical project? |
| Q4 | **Should Deja Vu fire on every prompt or only on code-change intent?** The existing prompt-submit hook already classifies intent as `code-change` vs. `general`. | (a) Fire on every prompt (maximum coverage). (b) Fire only on `code-change` intent (targeted). (c) Fire on `code-change` prompts always; fire on `general` prompts only if they mention technology/pattern keywords. | **(c)** — Hybrid. Code-change prompts always trigger Deja Vu (highest risk). General prompts trigger only if they contain technology/pattern keywords from the signal extraction. This minimizes unnecessary Cipher queries while maintaining coverage. | User testing: does firing on every code-change prompt feel noisy for rapid iteration sessions? |
| Q5 | **How should Deja Vu interact with Momentum?** Both features read from Cipher and context tree. Momentum captures session state; Deja Vu captures failure patterns. | (a) Independent — no direct interaction. (b) Momentum feeds Deja Vu — reverted/abandoned tasks in session snapshots auto-create pattern candidates. (c) Deja Vu feeds Momentum — active warnings are included in session snapshots for context. | **(b) + (c)** — Bidirectional but lazy. Momentum feeds Deja Vu at session end (revert detection). Deja Vu feeds Momentum at session start (active warnings as context). But this is a P2 integration — P0 ships them independently. | Coordinate with Momentum implementation schedule. |

### 8.2 Technical Unknowns

| # | Unknown | Risk Level | Investigation Plan |
|---|---------|-----------|-------------------|
| T1 | **Cipher hybrid query latency with tag filtering.** Does adding a `type: deja_vu_pattern` filter to Cipher's semantic search stay under 300ms with 500+ patterns? | Medium | Benchmark with synthetic pattern data. If slow, implement a local signal index (JSON file) for fast pre-filtering before Cipher query. |
| T2 | **Signal extraction accuracy.** Can regex + keyword matching reliably extract meaningful signals from natural language prompts? | Medium | Prototype with 50 diverse prompts. Measure signal relevance. If accuracy is below 70%, consider a lightweight NLP model or prompt structure analysis. |
| T3 | **Multiple hook handler output merging.** When two hooks are registered for the same event (e.g., existing `prompt-submit.sh` and new `deja-vu-prompt-submit.sh`), how does Claude Code merge their JSON outputs? | High | Test with two `UserPromptSubmit` handlers returning different JSON keys. If outputs are not merged, may need to integrate Deja Vu inline with the existing hook (fallback to option Q1-a). |
| T4 | **Pattern extraction reliability from post-session curation.** Can the existing `cipher_extract_and_operate_memory` flow reliably identify reverted/abandoned approaches and tag them as Deja Vu patterns? | Medium | Prototype with 10 sessions that include reverts. Check if the extraction model captures the revert reason accurately. If unreliable, add explicit agent instructions to tag reverts manually. |
| T5 | **Cross-project query latency with linked workspaces.** Querying multiple Cipher collections (one per linked project) could multiply latency. | Low (P1) | Benchmark with 3 linked workspaces. If slow, implement parallel queries with a combined timeout of 500ms. |

### 8.3 Scope Boundary Questions

| # | Question | Current Answer | May Change If |
|---|----------|---------------|---------------|
| S1 | Does Deja Vu replace `/xgh-ask` for finding past failures? | **No.** `/xgh-ask` is pull-based (developer asks). Deja Vu is push-based (system warns). They complement each other. | `/xgh-ask` adds a "related Deja Vu patterns" section to its results, making them partially redundant for failure queries. |
| S2 | Should Deja Vu patterns be part of the context tree? | **No.** Patterns are operational metadata (confidence scores, feedback history, decay). The context tree is for durable, human-authored knowledge. Decision records (which patterns reference) live in the context tree. | A "promoted patterns" flow allows particularly valuable patterns to be formalized as context tree decision records. |
| S3 | Does Deja Vu work without Cipher? | **No.** Cipher is a hard dependency. The pattern library is stored in Cipher. Without Cipher, Deja Vu has no pattern store and cannot function. | A future "lightweight mode" could use a local JSON file as pattern store for projects without Cipher, but this is not planned. |
| S4 | Is Momentum a prerequisite for Deja Vu? | **No.** They are independent features. Deja Vu's pattern extraction runs during the existing post-session curation step, not through Momentum's session snapshots. | P2 integration: Momentum's revert detection feeds Deja Vu pattern candidates. But P0 ships independently. |

---

## Appendix A: Implementation Sequence

| Phase | Scope | Components | Est. Effort |
|-------|-------|-----------|-------------|
| **Phase 1** | P0 Core (signal extraction + pattern matching + fast warnings) | `deja-vu-prompt-submit.sh` (hook), signal extraction module, Cipher query integration, fast-mode warning template, `deja_vu_pattern` schema, `.xgh/config.yaml` Deja Vu section, enabled/disabled check | 3-4 days |
| **Phase 2** | P0 Polish (pattern creation + feedback loop + dismiss flow) | Post-session pattern extraction (extend curation flow), feedback loop (dismiss/accept/resolve), confidence adjustment logic, temporal decay at query time, specificity threshold | 2-3 days |
| **Phase 3** | P0 Complete (skill + command + archetype defaults) | `skills/deja-vu/deja-vu.md`, `commands/deja-vu.md`, `modules/deja-vu/module.yaml`, `techpack.yaml` registration, archetype defaults, edge case handling, tests | 2-3 days |
| **Phase 4** | P1 Enhanced (PreToolUse + PostToolUse + rich mode + cross-project) | `deja-vu-pre-tool.sh`, `deja-vu-post-tool.sh`, rich mode LLM composition, context tree excerpt integration, cross-project queries, warning analytics log | 3-4 days |

**Total estimated effort:** 7-10 days for P0. 10-14 days for P0+P1. P2 features deferred until pattern library reaches critical mass (~50 patterns).

---

## Appendix B: Pattern Schema Evolution

| Version | Additions | Breaking Changes |
|---------|-----------|-----------------|
| **v1** (P0 launch) | `id`, `signals[]`, `area`, `outcome`, `severity`, `reason`, `original_session`, `ticket`, `related_decisions[]`, `confidence_adjustments[]`, `resolved_at`, `deprecated_at` | N/A (initial version) |
| **v2** (P1) | `failure_signature` (for PostToolUse matching), `source_project` (for cross-project), `excerpt` (cached decision record excerpt), `warning_count` (firing frequency) | None — additive only |
| **v3** (P2) | `promoted_to_context_tree` (boolean), `compliance_log_entries[]`, `created_by` (auto vs. manual) | None — additive only |

**Compatibility rule:** Deja Vu must always read patterns from older schema versions. Unknown fields are ignored. Missing fields use sensible defaults (empty arrays, `null`, `false`).

---

## Appendix C: Self-Review Notes

**Engineer lens:**
- Fixed: Added explicit performance guard for the prompt-submit hook extension — if Deja Vu pipeline exceeds 500ms, it aborts without blocking the existing hook behavior.
- Fixed: Clarified that Deja Vu registers as a *separate* hook handler rather than modifying the existing `prompt-submit.sh`, keeping modules decoupled.
- Fixed: Added T3 (multiple hook handler output merging) as a high-risk technical unknown, since the PRD's architecture depends on Claude Code merging outputs from multiple handlers on the same event.

**PM lens:**
- Fixed: Added quantified baseline metrics to the problem statement (Section 1.1) — was missing concrete numbers that justify the feature.
- Fixed: Strengthened the feedback loop section (4.3) with a clear table mapping actions to effects, making the self-calibration mechanism concrete.
- Fixed: Added area consolidation to the false positive management section (5.3) to address the "warning fatigue in hotspot areas" concern.

**Designer lens:**
- Fixed: Added the "Multiple Patterns Match" edge case (4.5) — original proposal did not address what happens when several patterns fire simultaneously.
- Fixed: Added the "Pattern Matches But Decision Record Is Missing" edge case — a broken link UX that needed explicit handling.
- Fixed: Ensured warning output fits the established xgh visual style (tables, emoji-accented headers, blockquoted excerpts) and stays under 15 lines in fast mode.

*This PRD is a living document. Update it as design decisions from Section 8 are resolved.*
