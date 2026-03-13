# xgh (extreme-go-horsebot) — Design Document

> MCS tech pack for team-shared self-learning memory, inspired by ByteRover, powered by Cipher, disciplined by Superpowers methodology.

**Date:** 2026-03-13
**Status:** Approved
**Architecture:** Approach B — Dual-Engine (Cipher vectors + custom context tree)

---

## 1. Problem Statement

Engineering teams at TradeRepublic use AI coding agents (primarily Claude Code) daily. Each session starts from zero — agents have no memory of past decisions, conventions, or learnings. Knowledge is trapped in individual sessions and lost when they end.

ByteRover solves this commercially, but TR needs:
- An internal solution with no external SaaS dependency
- Team-wide knowledge sharing across repos
- Plug-and-play setup via MCS (zero manual configuration)
- Multi-agent support (Claude Code preferred, but any MCP-compatible agent works)

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      xgh MCS Tech Pack                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────────┐ │
│  │ Claude Code   │    │ Other Agents │    │ xgh CLI       │ │
│  │ (hooks +      │    │ (Cursor,     │    │ (skills +     │ │
│  │  skills)      │    │  Codex, etc) │    │  commands)    │ │
│  └──────┬───────┘    └──────┬───────┘    └──────┬────────┘ │
│         │                   │                   │          │
│         ▼                   ▼                   ▼          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Cipher MCP Server                      │   │
│  │  memory_search · extract_and_operate_memory         │   │
│  │  workspace_search · workspace_store                 │   │
│  │  knowledge_graph · reasoning_traces                 │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                  │
│         ┌───────────────┼───────────────┐                  │
│         ▼               ▼               ▼                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │  Qdrant    │  │  SQLite    │  │  Ollama    │           │
│  │  (vectors) │  │  (sessions)│  │  (LLM+emb) │           │
│  └────────────┘  └────────────┘  └────────────┘           │
│                         │                                  │
│                         ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │            Context Tree Sync Layer                  │   │
│  │   Cipher vectors ←→ .xgh/context-tree/ markdown     │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                  │
│                         ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         .xgh/context-tree/  (git-committed)         │   │
│  │  ├── domain/ → topic/ → subtopic/                   │   │
│  │  ├── YAML frontmatter (importance, maturity)        │   │
│  │  ├── _index.md (compressed summaries)               │   │
│  │  └── _manifest.json (registry)                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Multi-Agent Collaboration Bus               │   │
│  │  Message protocol · Workflow templates ·             │   │
│  │  Agent registry · Dispatch layer                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Dual-Engine Design

| Engine | Purpose | Storage | Search |
|--------|---------|---------|--------|
| **Cipher** | Semantic memory, reasoning traces, workspace | Qdrant vectors + SQLite | Vector similarity (embeddings) |
| **Context Tree** | Human-readable knowledge, git-shareable | `.xgh/context-tree/*.md` | BM25 keyword + frontmatter scoring |

**Why both?** Cipher's vector search has superior semantic recall. But git-committed markdown is auditable, reviewable in PRs, and shareable without shared infrastructure. The sync layer keeps them consistent.

### Sync Layer

On **curate** (new knowledge enters the system):
1. Cipher stores the vector embedding + metadata
2. Sync layer classifies into domain/topic/subtopic
3. Writes/updates the corresponding `.md` file in the context tree
4. Updates `_manifest.json` and parent `_index.md` files

On **query**:
1. Cipher semantic search runs in parallel with context tree BM25
2. Results are merged and ranked: `score = (0.5 × cipher_similarity + 0.3 × bm25_score + 0.1 × importance + 0.1 × recency) × maturityBoost`
3. Core maturity files get ×1.15 boost (adopted from ByteRover)

## 3. Context Tree Structure

Adopted from ByteRover's proven hierarchy:

```
.xgh/context-tree/
├── _manifest.json              # Registry of all entries
├── authentication/             # Domain
│   ├── context.md              # Auto-generated domain overview
│   ├── _index.md               # Compressed summary (YAML frontmatter + condensed content)
│   ├── jwt-implementation/     # Topic
│   │   ├── context.md
│   │   ├── token-refresh.md    # Knowledge file
│   │   └── refresh-tokens/     # Subtopic
│   │       └── rotation.md
│   └── oauth-flow/
│       └── github-sso.md
├── api-design/
│   └── rest-conventions.md
└── _archived/                  # Low-importance drafts
    └── authentication/
        └── old-session-mgmt.stub.md
```

### Knowledge File Format

```yaml
---
title: JWT Token Refresh Strategy
tags: [auth, jwt, security]
keywords: [refresh-token, rotation, expiry]
importance: 78            # 0-100, increases with usage
recency: 0.85             # 0-1, decays with ~21-day half-life
maturity: validated        # draft → validated (≥65) → core (≥85)
related:
  - authentication/oauth-flow/github-sso
accessCount: 12
updateCount: 3
createdAt: 2026-03-13T10:00:00Z
updatedAt: 2026-03-13T14:30:00Z
source: auto-curate       # auto-curate | manual | agent-collaboration
fromAgent: claude-code
---

## Raw Concept
[Technical details, file paths, execution flow]

## Narrative
[Structured explanation, rules, examples]

## Facts
- category: convention
  fact: Refresh tokens rotate on every use with a 7-day absolute expiry
- category: decision
  fact: Chose rotation over sliding window to limit blast radius of token theft
```

### Scoring & Maturity

| Metric | Behavior |
|--------|----------|
| **Importance** | +3 per search hit, +5 per update, +10 per manual curate |
| **Recency** | Exponential decay, ~21-day half-life |
| **Maturity** | draft → validated (≥65 importance) → core (≥85). Hysteresis: −35/−60 to demote |
| **Archive** | Draft files with importance <35 → `.stub.md` (searchable ghost) + `.full.md` (lossless backup) |

## 4. Hook-Driven Self-Learning

The core learning loop, inspired by ByteRover's decision table pattern:

### UserPromptSubmit Hook

Fires on every user prompt. Injects a decision table:

```
┌─ xgh Decision Table ─────────────────────────────────┐
│                                                       │
│  About to write code?                                 │
│  → cipher_memory_search FIRST (check prior knowledge) │
│  → query context tree for conventions                 │
│                                                       │
│  Just wrote/modified code?                            │
│  → cipher_extract_and_operate_memory                  │
│  → sync new learnings to context tree                 │
│                                                       │
│  Made an architectural decision?                      │
│  → curate decision + rationale + alternatives         │
│                                                       │
│  Hit a bug and fixed it?                              │
│  → curate root cause + fix + trigger conditions       │
│                                                       │
│  Reviewing a PR?                                      │
│  → query context tree for related decisions           │
│  → curate any new patterns discovered                 │
│                                                       │
└───────────────────────────────────────────────────────┘
```

### SessionStart Hook

On session start:
1. Load context tree `_manifest.json` for the current repo
2. Inject top-5 most relevant core-maturity knowledge files as context
3. Inject team workspace highlights (cross-repo conventions)

### SessionEnd Hook (Post-Session Curation)

On session end:
1. Extract session learnings via `cipher_extract_and_operate_memory`
2. Sync new/updated entries to context tree
3. Update importance scores for accessed entries

## 5. Multi-Agent Collaboration Bus

Abstracted from the [ByteRover-Claude-Codex-Collaboration](https://github.com/trietdeptrai/Byterover-Claude-Codex-Collaboration-) pattern. Instead of hardcoding Claude→Codex, xgh provides a **generic dispatch layer**.

### Message Protocol

Every inter-agent message in Cipher workspace uses structured metadata:

```yaml
type: plan | review | feedback | result | decision | question
status: pending | in_progress | completed
from_agent: claude-code     # who wrote it
for_agent: "*"              # who should read it (* = broadcast)
thread_id: feat-123         # groups related messages
priority: normal | high | urgent
created_at: 2026-03-13T10:00:00Z
```

### Agent Registry

xgh maintains a registry of available agents and their capabilities:

```yaml
agents:
  claude-code:
    type: primary
    capabilities: [architecture, implementation, planning, review]
    integration: hooks + skills + MCP
  codex:
    type: secondary
    capabilities: [fast-implementation, code-review]
    integration: MCP + bash-invocation
  cursor:
    type: secondary
    capabilities: [ide-editing, refactoring]
    integration: MCP
  custom:
    type: extensible
    capabilities: [user-defined]
    integration: MCP
```

### Workflow Templates

Reusable multi-agent patterns:

**plan-review** (2 agents):
```
Agent A → PLAN (store) → Agent B → REVIEW (store) → Agent A → IMPLEMENT
```

**parallel-impl** (N agents):
```
Agent A → SPLIT tasks → Agents B,C,D → IMPLEMENT (parallel) → Agent A → MERGE + REVIEW
```

**validation** (2 agents):
```
Agent A → IMPLEMENT (store) → Agent B → VALIDATE (store) → feedback loop
```

**security-review** (chain):
```
Agent A → IMPLEMENT → Agent B → SECURITY_REVIEW → Agent A → FIX → Agent B → RE-REVIEW
```

### Dispatch Layer

```
┌─────────────┐     ┌──────────────────────┐     ┌─────────────┐
│  Agent A     │     │   Cipher Workspace   │     │  Agent B     │
│  (any agent) │────▶│                      │◀────│  (any agent) │
│              │     │  Structured messages: │     │              │
│  STORE:      │     │  ┌─ PLAN:  ...      │     │  SEARCH:     │
│  type: plan  │     │  ├─ REVIEW: ...     │     │  type: plan  │
│  for: review │     │  ├─ FEEDBACK: ...   │     │  status: new │
│              │     │  └─ RESULT: ...     │     │              │
└─────────────┘     └──────────────────────┘     └─────────────┘
```

The dispatch layer:
1. Watches for new messages in Cipher workspace
2. Routes to the appropriate agent based on `for_agent` field
3. Invokes the agent with the message context
4. Monitors for response and updates thread status

## 6. Superpowers-Inspired Skill Methodology

xgh skills follow the Superpowers framework's proven patterns for maximum quality.

### Skill Design Principles (from Superpowers)

| Principle | Application in xgh |
|-----------|-------------------|
| **TDD for documentation** | Every skill is pressure-tested against agent failure modes before shipping |
| **Iron Laws** | Each discipline skill has one non-negotiable rule (e.g., "NO CODE WITHOUT QUERYING MEMORY FIRST") |
| **Rationalization Tables** | Document actual agent excuses for skipping memory queries, then close loopholes |
| **Hard Gates** | Binary pass/fail checkpoints that block progression |
| **Fresh context per subagent** | Multi-agent tasks dispatch clean subagents to prevent context drift |
| **Evidence before claims** | Verification-before-completion applies to memory operations too |
| **2-5 minute task chunks** | Context tree curation broken into atomic operations |

### Skill Types

**Rigid skills** (mandatory process, no deviation):
- `xgh:continuous-learning` — the auto-query/auto-curate loop
- `xgh:memory-verification` — verify memory was actually stored/retrieved correctly
- `xgh:context-tree-maintenance` — scoring, maturity promotion, archival

**Flexible skills** (guidance, adaptable):
- `xgh:curate-knowledge` — how to structure knowledge for maximum retrieval
- `xgh:query-strategies` — tiered query routing patterns
- `xgh:agent-collaboration` — multi-agent workflow templates

### Enforcement Mechanisms

**The xgh Iron Law:**
> `EVERY CODING SESSION MUST QUERY MEMORY BEFORE WRITING CODE AND CURATE LEARNINGS BEFORE ENDING.`

**Rationalization Table** (anticipated agent excuses):

| Agent Thought | Reality |
|---------------|---------|
| "This is a simple change, no need to check memory" | Simple changes cause the most repeated mistakes |
| "I already know the conventions" | Your training data ≠ this team's conventions |
| "Curating this would slow me down" | 30 seconds now saves 30 minutes next session |
| "This learning is too specific to store" | Specific learnings are the most valuable |
| "Memory search returned nothing relevant" | Refine query, check context tree, then proceed |

## 7. CLI Commands & Skills

### Slash Commands (Claude Code)

| Command | Description |
|---------|-------------|
| `/xgh query <question>` | Search memory + context tree, return ranked results |
| `/xgh curate <knowledge>` | Store knowledge in Cipher + sync to context tree |
| `/xgh curate -f <file>` | Curate from file contents (up to 5 files) |
| `/xgh curate -d <dir>` | Curate from directory |
| `/xgh push` | Push context tree to git remote |
| `/xgh pull` | Pull context tree from git remote |
| `/xgh status` | Show memory stats, context tree health, agent registry |
| `/xgh collaborate <workflow> <agents>` | Start multi-agent workflow |

### Skills (auto-triggered)

| Skill | Trigger |
|-------|---------|
| `xgh:continuous-learning` | Every session (via hooks) |
| `xgh:curate-knowledge` | When agent detects new patterns/decisions |
| `xgh:query-strategies` | When agent needs to search prior knowledge |
| `xgh:agent-collaboration` | When multi-agent workflow is requested |
| `xgh:context-tree-maintenance` | Periodic (scoring updates, archival) |

## 8. Hub / Skill Marketplace

Inspired by ByteRover's BRV Hub and the MCS tech pack ecosystem.

### Hub Structure

xgh bundles are shareable packages of:
- **Context bundles** — pre-curated knowledge for specific domains (e.g., "TR iOS conventions", "TR backend patterns")
- **Workflow templates** — multi-agent collaboration patterns
- **Custom skills** — domain-specific xgh skills

### Distribution

Since xgh is an MCS tech pack, hub items can be:
1. **Git repos** — installable via `mcs pack add <repo>`
2. **Bundled in the tech pack** — shipped as part of xgh itself
3. **Team-shared** — via Cipher workspace memory (no git required)

## 9. MCS Tech Pack Structure

```yaml
schemaVersion: 1
identifier: xgh
displayName: "xgh (extreme-go-horsebot)"
description: "Self-learning memory layer with team sharing, inspired by ByteRover"
author: "TradeRepublic"

components:
  # Infrastructure (plug-and-play)
  - id: ollama
    description: "Local LLM runtime"
    brew: ollama

  - id: ollama-models
    description: "Pull required models"
    dependencies: [ollama]
    shell: "ollama pull llama3.2:3b && ollama pull nomic-embed-text"
    type: shellCommand
    doctorChecks:
      - type: shellScript
        name: "Ollama models"
        command: "ollama list | grep -q llama3.2:3b && ollama list | grep -q nomic-embed-text"

  - id: qdrant
    description: "Vector store"
    brew: qdrant

  - id: cipher
    description: "Cipher MCP memory server"
    mcp:
      command: npx
      args: ["-y", "@byterover/cipher"]
      env:
        VECTOR_STORE_TYPE: qdrant
        VECTOR_STORE_URL: "http://localhost:6333"
        CIPHER_LOG_LEVEL: info
        SEARCH_MEMORY_TYPE: both
      scope: project

  # Hooks (continuous learning)
  - id: session-start-hook
    description: "Load context tree on session start"
    hookEvent: SessionStart
    hook:
      source: hooks/session-start.sh
      destination: xgh-session-start.sh

  - id: prompt-submit-hook
    description: "Decision table: auto-query + auto-curate"
    hookEvent: UserPromptSubmit
    hook:
      source: hooks/prompt-submit.sh
      destination: xgh-prompt-submit.sh

  # Skills
  - id: continuous-learning
    description: "Core self-learning loop"
    skill:
      source: skills/continuous-learning
      destination: xgh-continuous-learning

  - id: curate-knowledge
    description: "Knowledge curation patterns"
    skill:
      source: skills/curate-knowledge
      destination: xgh-curate-knowledge

  - id: query-strategies
    description: "Tiered query routing"
    skill:
      source: skills/query-strategies
      destination: xgh-query-strategies

  - id: agent-collaboration
    description: "Multi-agent workflow patterns"
    skill:
      source: skills/agent-collaboration
      destination: xgh-agent-collaboration

  - id: context-tree-maintenance
    description: "Scoring, maturity, archival"
    skill:
      source: skills/context-tree-maintenance
      destination: xgh-context-tree-maintenance

  # Commands
  - id: query-command
    description: "Search memory + context tree"
    command:
      source: commands/query.md
      destination: xgh-query.md

  - id: curate-command
    description: "Store knowledge"
    command:
      source: commands/curate.md
      destination: xgh-curate.md

  - id: collaborate-command
    description: "Multi-agent workflows"
    command:
      source: commands/collaborate.md
      destination: xgh-collaborate.md

  - id: status-command
    description: "Memory stats and health"
    command:
      source: commands/status.md
      destination: xgh-status.md

  # Agents
  - id: context-curator
    description: "Subagent for context tree maintenance"
    agent:
      source: agents/context-curator.md
      destination: xgh-context-curator.md

  - id: collaboration-dispatcher
    description: "Subagent for multi-agent orchestration"
    agent:
      source: agents/collaboration-dispatcher.md
      destination: xgh-collaboration-dispatcher.md

  # Settings
  - id: settings
    description: "Claude Code settings for xgh"
    isRequired: true
    settingsFile: config/settings.json

  # Gitignore
  - id: gitignore
    description: "Ignore local xgh data"
    isRequired: true
    gitignore:
      - .xgh/local/
      - .xgh/context-tree/_index.md
      - data/cipher-sessions.db*

templates:
  - sectionIdentifier: xgh-instructions
    contentFile: templates/instructions.md

prompts:
  - key: TEAM_NAME
    type: input
    label: "Team name (for workspace memory)"
    default: "tr-engineering"

  - key: CONTEXT_TREE_PATH
    type: input
    label: "Context tree path"
    default: ".xgh/context-tree"
```

## 10. Plug-and-Play Setup Flow

After `mcs pack add xgh && mcs sync`:

```
Step 1: Install Ollama (brew)           ✓ auto
Step 2: Pull llama3.2:3b model          ✓ auto
Step 3: Pull nomic-embed-text model     ✓ auto
Step 4: Install Qdrant (brew)           ✓ auto
Step 5: Configure Cipher MCP server     ✓ auto
Step 6: Install hooks                   ✓ auto
Step 7: Install skills + commands       ✓ auto
Step 8: Initialize .xgh/context-tree/   ✓ auto (via configureProject script)
Step 9: Prompt for team name            ? one question
Step 10: Ready to use                   🐴
```

**Zero manual steps** beyond answering the team name prompt.

## 11. Key Influences & Attribution

| Source | What we adopted |
|--------|----------------|
| **ByteRover** | Context tree hierarchy, YAML frontmatter, scoring/maturity, hook decision table, tiered query routing, hub concept |
| **Cipher** | Vector memory, knowledge graph, reasoning traces, dual System 1/2 memory, workspace sharing, MCP server |
| **Superpowers** | Skill methodology (TDD for docs, iron laws, rationalization tables, hard gates), subagent-driven development, fresh-context-per-task, verification-before-completion |
| **ByteRover-Claude-Codex-Collaboration** | Multi-agent communication via shared memory, structured message protocol, workflow templates |
| **MCS** | Tech pack distribution, plug-and-play installation, managed settings composition |
