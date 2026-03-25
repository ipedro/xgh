# Context Drops — Product Requirements Document

**Feature:** Context Drops (shareable knowledge snapshots for xgh)
**Author:** Pedro (via Claude Code)
**Date:** 2026-03-15
**Status:** PRD — ready for engineering review
**Proposal Source:** [`collaboration.md`](./collaboration.md)

---

## 1. Overview

### 1.1 Problem Statement: Trapped Knowledge

xgh makes individual projects extraordinarily context-rich. Cipher accumulates semantic memory, the context tree captures validated decisions, and reasoning chains record the "why" behind non-obvious choices. But all of that knowledge is **trapped inside the project that created it**. Knowledge accumulates vertically (deeper within one project) but never flows horizontally (across projects, teams, or people).

**Quantified impact:**

| Metric | Value | Source |
|--------|-------|--------|
| Time for a new hire's agent to reach productivity | 3-4 weeks | Enterprise PM self-report |
| Sessions to re-teach agent established patterns in a new project | 2-3 sessions (2-5 min context-building each) | Solo developer self-report |
| Percentage of OSS contributor PRs that violate undocumented conventions | ~30-40% | Maintainer anecdote |
| Cross-team handoff context lost (SDK knowledge not transferred) | 100% — zero Cipher memory crosses project boundaries | Architecture constraint |
| Time to manually re-explain architecture to a fresh agent | 5-15 minutes per session start | Momentum PRD baseline |
| Annual cost of re-explaining per developer (at 10 min/day across projects) | ~42 hours | 250 working days x 10 min |

The irony: the knowledge already exists in structured, machine-readable form (Cipher vectors, context tree markdown, reasoning chains). There is no mechanism to package it and move it to where it is needed.

### 1.2 Vision

With Context Drops, knowledge flows between projects, teams, and people as easily as code does via git. A developer runs `/xgh-drop` to export a curated bundle of their project's accumulated wisdom. Another developer (or the same developer in a new project) runs `/xgh-absorb` to instantly hydrate their agent with that knowledge. Six months of accumulated patterns, decisions, and gotchas — transferred in one command.

**Before Context Drops:**
```
New project → Agent has zero context → 2-3 sessions re-explaining architecture →
Agent slowly learns patterns → Still misses team conventions → Weeks to full productivity
```

**After Context Drops:**
```
New project → /xgh-absorb mature-project.drop → Agent knows architecture, patterns,
conventions, and reasoning from day zero → First prompt is productive (<15s)
```

### 1.3 Success Metrics

| Metric | Current Baseline | Target | Measurement Method |
|--------|-----------------|--------|-------------------|
| Agent context-building time (new project) | 2-3 sessions (10-15 min total) | 0 sessions (one `/xgh-absorb` command) | Time from project init to first agent response that uses absorbed patterns |
| New hire onboarding (agent readiness) | 3-4 weeks | <1 day | Time until agent stops suggesting patterns that violate team conventions |
| Cross-project knowledge reuse | 0% (manual re-explaining) | >80% of established patterns transfer | Absorbed drop knowledge surfaced in agent responses without re-explaining |
| OSS contributor convention violations | ~30-40% of PRs | <10% of PRs (after absorbing maintainer drop) | PR review rejection rate for convention violations |
| Drop export time | N/A | <30s for scoped export, <2min for full project | Wall-clock time for `/xgh-drop` to produce a bundle |
| Drop absorb time | N/A | <15s (same model), <60s (re-embedding required) | Wall-clock time for `/xgh-absorb` to hydrate local memory |
| Drop file size (typical scoped export) | N/A | <5MB | File size of `.drop` bundle |
| PII leak rate in exported drops | N/A | 0 PII items in exported drops | Automated PII scan of exported bundles |

---

## 2. User Personas & Stories

### 2.1 Solo Dev — "The Project Hopper"

**Persona:** Sofia, a developer who maintains three Swift packages that all follow the same architecture: protocol-oriented, async/await, dependency injection via factory closures. She starts a new package every few months.

**Before:** Sofia opens her new package. Her agent starts from scratch — suggesting delegate patterns instead of factory closures, using the wrong naming conventions, and structuring tests differently from her established style. It takes 2-3 sessions before the agent catches up. Every new project re-pays this tax.

**Story:** As a solo developer who maintains multiple projects with consistent architecture patterns, I want to export my established patterns from a mature project and absorb them into a new one, so that my agent uses my preferred conventions from the very first prompt.

**After:** Sofia runs `/xgh-drop --scope "architecture patterns, naming conventions, test structure"` in her most mature package. She gets `swift-architecture.drop`. In her new package, she runs `/xgh-absorb swift-architecture.drop`. First session, first prompt: the agent already uses factory closures, names protocols correctly, and structures tests her way. Two days of context-building compressed to 10 seconds.

**Delight factor:** "Start every project with everything I learned from the last 5."

---

### 2.2 OSS Contributor — "The Context Gap Closer"

**Persona:** Jordan, an open-source library maintainer shipping a major version bump. Contributors file issues for "bugs" that are deliberate design decisions. PRs regularly violate undocumented conventions.

**Before:** Jordan writes a migration guide in the README. Maybe 20% of contributors read it. Their agents have no idea why the API looks the way it does — the deliberate trade-offs, the regulatory constraints, the performance decisions. Every PR review includes comments like "this is intentional, see issue #47."

**Story:** As an OSS maintainer, I want to publish curated knowledge drops alongside releases that contain my design rationale, patterns, and gotchas, so that contributors' agents understand my project's conventions before they write their first line of code.

**After:** Jordan publishes `v3.0-migration.drop` alongside the release. It contains every architecture decision, every pattern that is intentional vs. accidental, and every migration gotcha. A contributor runs `/xgh-absorb v3.0-migration.drop` before starting a PR. Their agent knows why the retry logic uses exactly 3 attempts (regulatory requirement), why the error type hierarchy looks unusual (composability with the middleware pattern), and which files are load-bearing.

**Delight factor:** "Contributors stop filing bugs for deliberate design decisions."

---

### 2.3 Enterprise — "The Onboarding Accelerator"

**Persona:** Marcus, a platform team PM with 40% annual turnover. New hires spend 3-4 weeks before their AI agent is productive — lacking institutional context about payment retry logic, auth token rotation patterns, and which Confluence pages are authoritative vs. outdated.

**Before:** Marcus asks senior engineers to schedule onboarding sessions, write Confluence pages, and answer Slack questions. The knowledge transfer is lossy, incomplete, and takes weeks. When the senior engineer leaves, the next onboarding cycle is even worse.

**Story:** As an enterprise PM, I want senior engineers to export their domain expertise as drops that new hires absorb on day one, so that onboarding time is measurable and dramatically shorter.

**After:** Marcus asks senior engineers to run `/xgh-drop --scope "domain expertise"` for their areas: `payments-domain.drop`, `auth-patterns.drop`, `testing-conventions.drop`. New hire runs `/xgh-absorb *.drop` on day one. Their agent immediately knows team conventions, can explain past decisions, and flags when the new hire is about to violate an established pattern. Marcus measures onboarding time dropping from 3 weeks to 3 days. He puts this in his quarterly review.

**Delight factor:** "Onboarding drops survive engineer turnover. The knowledge is in the drop, not in someone's head."

---

### 2.4 OpenClaw — "The Cross-Context Bridge"

**Persona:** Sam, who uses xgh's OpenClaw archetype as a personal AI assistant. They have professional projects at work and personal projects at home. Both have rich Cipher memory that does not cross boundaries.

**Before:** Sam built an elegant caching strategy in their work project 4 months ago. They remember the shape of the solution but not the implementation details. That reasoning chain exists in the work project's Cipher memory, inaccessible from the personal project.

**Story:** As an OpenClaw user who works across personal and professional contexts, I want to selectively export knowledge from one context and absorb it into another, so that insights I develop anywhere become available everywhere I need them.

**After:** Sam runs `/xgh-drop --scope "caching patterns, retry strategies"` in their work project. The PII filter strips internal URLs, team Slack handles, and service names. The exported drop contains the pure architectural reasoning. Sam runs `/xgh-absorb caching-patterns.drop` in their personal project. The patterns transfer; the sensitive details do not.

**Delight factor:** "My personal agent learns from my professional agent without leaking company data."

---

## 3. Requirements

### 3.1 Must Have (P0) — Core Drop Export & Import

These requirements form the minimum viable Context Drops. Without all of them, the feature does not deliver its core promise.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **CD-P0-01** | **Drop export command (`/xgh-drop`):** The agent exports a curated knowledge bundle from the current project's Cipher memory and context tree. | Skill file `skills/drop-compiler/drop-compiler.md` and command `commands/drop.md` exist. Command prompts for scope (whole project, specific topics, date range). Produces a `.drop` directory at the specified output path. |
| **CD-P0-02** | **Drop import command (`/xgh-absorb`):** The agent imports a `.drop` bundle into the current project's Cipher memory and context tree. | Skill file `skills/drop-hydrator/drop-hydrator.md` and command `commands/absorb.md` exist. Command accepts a path (local directory, tarball, or URL). Shows a manifest summary before importing. Merges into local Cipher + context tree. |
| **CD-P0-03** | **Drop manifest (`manifest.json`):** Every `.drop` bundle contains a machine-readable manifest with metadata: author, date, xgh version, scope tags, content hash, embedding model, entry count. | Manifest conforms to `config/drop-manifest.schema.json`. Import validates manifest before proceeding. Missing or invalid manifest aborts import with a clear error. |
| **CD-P0-04** | **Context tree fragment export:** The drop compiler extracts a subset of `.xgh/context-tree/` markdown files matching the requested scope. | Exported files preserve directory structure relative to context tree root. Frontmatter (title, importance, maturity) is preserved. Files are human-readable in the `.drop` bundle without any tooling. |
| **CD-P0-05** | **Vector export (Cipher):** The drop compiler exports Cipher vectors (embeddings + source text + metadata) matching the requested scope as `.jsonl`. | Each line in `vectors.jsonl` contains: `id`, `vector` (float array), `text` (source text for re-embedding), `metadata` (tags, timestamps, type). Source text is always included to enable cross-model re-embedding. |
| **CD-P0-06** | **Reasoning chain export:** The drop compiler exports serialized reasoning memories matching the requested scope. | Exported as individual JSON files in `reasoning-chains/`. Each contains: `question`, `steps[]`, `outcome`, `metadata`. |
| **CD-P0-07** | **PII filtering at export time:** The drop compiler strips personally identifiable information before writing the bundle. | Default filters: email addresses, Slack handles (@user), internal URLs (*.internal.*, *.corp.*), IP addresses, API keys/tokens (common patterns). Configurable via `.xgh/config.yaml` under `modules.drops.pii_filters[]`. Filter runs on all text content (context tree files, vector source text, reasoning chain text). Export log reports number of redactions. |
| **CD-P0-08** | **Provenance tagging on import:** Every piece of knowledge imported from a drop carries a `source_drop` metadata tag with the drop's name and version. | Context tree files imported from drops include a frontmatter field: `source_drop: "payments-patterns v1.0"`. Cipher vectors injected from drops include metadata: `source_drop`, `drop_version`, `absorbed_at`. Provenance enables selective purge: "Remove everything from this drop." |
| **CD-P0-09** | **Conflict resolution on import:** When imported context tree files conflict with existing local files, the hydrator resolves conflicts. | Three strategies available: `keep-both` (rename imported file with `.drop` suffix), `prefer-newer` (compare timestamps), `ask` (prompt the user). Default strategy: `keep-both`. Strategy configurable via `--conflict` flag on `/xgh-absorb`. |
| **CD-P0-10** | **Vector compatibility handling:** When the importing project uses a different embedding model than the drop, vectors are re-embedded from source text. | If `manifest.json` `embedding_model` matches local config: inject vectors directly (zero-cost). If models differ: re-embed from `text` field in `vectors.jsonl` using local model. Re-embedding logged with count and duration. |
| **CD-P0-11** | **Drop listing command (`/xgh-drops`):** List available drops (local `.drop` directories in the project or a specified path). | Command `commands/drops.md` exists. Shows: drop name, date, scope tags, entry count, size. Supports `--path <dir>` flag to scan a specific directory. |
| **CD-P0-12** | **Human-readable README:** Every exported `.drop` bundle includes a `README.md` with a human-readable summary of what the drop contains. | Auto-generated by the compiler. Includes: title, scope description, entry counts (context tree files, vectors, reasoning chains), creation date, source project name. A human can open the `.drop` directory and understand its contents without tooling. |
| **CD-P0-13** | **techpack.yaml registration:** Context Drops components registered in `techpack.yaml`. | New component IDs: `drop-compiler-skill`, `drop-hydrator-skill`, `drop-command`, `absorb-command`, `drops-command`, `drop-manifest-schema`. Components follow existing schema patterns. |
| **CD-P0-14** | **Config integration:** Context Drops configuration lives in `.xgh/config.yaml` under `modules.drops`. | Keys: `enabled` (bool), `default_output_path` (string, default: `.drops/`), `pii_filters[]` (custom redaction patterns), `default_conflict_strategy` (string: `keep-both`/`prefer-newer`/`ask`). |

### 3.2 Should Have (P1) — Enhanced Distribution & Curation

These features differentiate Context Drops from a manual copy-paste of Cipher exports.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **CD-P1-01** | **URL-based import:** `/xgh-absorb` accepts a URL (tarball) in addition to local paths. | Supports `https://` URLs. Downloads to a temp directory, validates manifest, then imports. Supports `.tar.gz` and `.zip` formats. Cleans up temp files after import. |
| **CD-P1-02** | **Git-hosted drops:** Drops committed to a git repo are discoverable via `/xgh-drops --repo <url>`. | Scans the repo root and `/.drops/` directory for `.drop` bundles. Lists available drops with metadata from manifests. Supports `--branch` flag. |
| **CD-P1-03** | **Selective import:** `/xgh-absorb` supports importing only a subset of a drop (e.g., only reasoning chains, only context tree, only vectors matching specific tags). | Flags: `--only context-tree`, `--only vectors`, `--only reasoning`, `--tags "architecture,patterns"`. Multiple `--only` flags can combine. Default: import everything. |
| **CD-P1-04** | **Drop versioning:** Drops carry a `version` field in the manifest. Re-absorbing a newer version of the same drop updates existing entries instead of duplicating. | Manifest includes `name` and `version` fields. On re-absorb: entries with matching `source_drop` name are replaced if the incoming version is newer. Rollback: `/xgh-absorb --rollback <drop-name>` removes all entries with that `source_drop` tag. |
| **CD-P1-05** | **Composite drops:** A drop's manifest can reference other drops as dependencies. Absorbing a composite drop absorbs its dependencies first. | Manifest field: `dependencies: [{name, version, url}]`. Import resolves dependencies recursively (max depth: 3). Circular dependency detection with clear error. |
| **CD-P1-06** | **Scope presets:** Common export scopes available as presets (e.g., `--scope architecture`, `--scope conventions`, `--scope onboarding`). | Presets defined in `.xgh/config.yaml` under `modules.drops.scope_presets`. Each preset maps to a set of Cipher query terms and context tree path filters. Built-in presets: `architecture`, `conventions`, `testing`, `all`. |
| **CD-P1-07** | **Export preview (dry run):** `/xgh-drop --dry-run` shows what would be exported without writing files. | Lists: context tree files to export, vector count by tag, reasoning chain count, estimated bundle size, PII redaction preview (count of items that would be redacted). |

### 3.3 Nice to Have (P2) — Future Possibilities

These are features Context Drops enables but does not implement in v1. They are documented to shape architectural decisions.

| ID | Requirement | Acceptance Criteria |
|----|------------|-------------------|
| **CD-P2-01** | **Drop registry:** Central or self-hosted registry where teams publish and discover drops. | Registry API: publish, search, download. Authentication via API key. Organization-scoped visibility. Think npm but for AI context. |
| **CD-P2-02** | **CI-generated drops:** GitHub Action that runs `/xgh-drop` on release, auto-publishing the project's current knowledge state. | Action YAML template in `templates/`. Triggered on release events. Publishes to registry or git release artifacts. |
| **CD-P2-03** | **Knowledge diffing:** Compare two drops (or two versions of the same drop) to see how understanding evolved. | `/xgh-drops --diff v1.drop v2.drop` shows: added entries, removed entries, modified entries, new reasoning chains. Useful for retrospectives. |
| **CD-P2-04** | **Memory Mesh via drops:** Automatic drop exchange between linked workspaces. The mesh becomes a protocol on top of drops. | Requires linked workspaces feature. Projects declare a publish cadence. Mesh protocol: publish, discover, absorb, with scoped permissions. |
| **CD-P2-05** | **Drop marketplace:** Community registry where OSS maintainers publish curated knowledge drops. | "The 20 most popular Swift architecture drops." Distribution channel for best practices consumed by machines, not just humans. |
| **CD-P2-06** | **Drop analytics:** Track which drops are most absorbed, which entries are most referenced, and which drops have the highest impact on reducing convention violations. | Metrics collected via provenance tags. Dashboard: absorption count, reference frequency, impact score. |

---

## 4. User Experience

### 4.1 Export Flow: `/xgh-drop`

The developer decides to export knowledge from a mature project. The flow is interactive but fast.

**Flow:**
```
1. Developer runs /xgh-drop
2. Agent prompts for scope (or uses --scope flag)
3. Drop Compiler queries Cipher + context tree for matching content
4. PII filter runs on all text content
5. Agent shows a preview: "Found 12 context tree files, 47 vectors, 8 reasoning chains. 3 PII items redacted."
6. Developer confirms
7. Bundle written to .drops/<name>.drop/
8. Agent shows summary with path and suggested distribution method
```

**What the developer sees:**

```markdown
## 🐴🤖 xgh drop

### Export Scope
| Source | Matched | Exported |
|--------|---------|----------|
| Context tree files | 18 | 12 (6 excluded: draft maturity) |
| Cipher vectors | 203 | 47 (scoped to "architecture, patterns") |
| Reasoning chains | 15 | 8 (matched scope) |

### PII Filtering
| Type | Redacted |
|------|----------|
| Email addresses | 1 |
| Internal URLs | 2 |
| Slack handles | 0 |

### Bundle Created

```
.drops/swift-architecture.drop/
  manifest.json          # v1.0 — 67 entries, embed model: ModernBERT
  context-tree/          # 12 markdown files (architecture, patterns)
  vectors.jsonl          # 47 vectors with source text
  reasoning-chains/      # 8 reasoning memories
  README.md              # Human-readable summary
```

**Size:** 1.2 MB
**Ready to share:** Copy the directory, commit to git, or host as a tarball.

*To import in another project: `/xgh-absorb .drops/swift-architecture.drop`*
```

### 4.2 Import Flow: `/xgh-absorb`

The developer (possibly a different person) absorbs a drop into their project.

**Flow:**
```
1. Developer runs /xgh-absorb <path-or-url>
2. Drop Hydrator reads manifest.json
3. Agent shows summary: what the drop contains, where it came from, compatibility info
4. Developer confirms
5. Context tree files merged (with conflict resolution)
6. Vectors injected into Cipher (re-embedded if model mismatch)
7. Reasoning chains imported with provenance tags
8. Agent shows summary of what was absorbed
```

**What the developer sees:**

```markdown
## 🐴🤖 xgh absorb

### Drop Summary
| | |
|---|---|
| **Name** | swift-architecture |
| **Version** | 1.0 |
| **Author** | Sofia |
| **Created** | 2026-03-10 |
| **Source project** | swift-payments |
| **Embedding model** | ModernBERT |

### Contents
| Type | Count |
|------|-------|
| Context tree files | 12 |
| Cipher vectors | 47 |
| Reasoning chains | 8 |

### Compatibility
| Check | Status |
|-------|--------|
| Embedding model match | ✅ Same model (zero-cost import) |
| Schema version | ✅ Compatible (v1) |
| Manifest integrity | ✅ Hash verified |

Proceed with import? (Y/n)

---

### Import Complete

| Type | Imported | Conflicts |
|------|----------|-----------|
| Context tree files | 12 | 1 (kept both — `api-patterns.md` → `api-patterns.drop.md`) |
| Cipher vectors | 47 | 0 |
| Reasoning chains | 8 | 0 |

All entries tagged with `source_drop: swift-architecture v1.0`.

*Your agent now has Sofia's architecture patterns. Try asking about factory closures or retry strategies.*
*To remove this drop later: `/xgh-absorb --rollback swift-architecture`*
```

### 4.3 List Flow: `/xgh-drops`

```markdown
## 🐴🤖 xgh drops

### Local Drops
| Name | Version | Created | Entries | Size |
|------|---------|---------|---------|------|
| swift-architecture | 1.0 | 2026-03-10 | 67 | 1.2 MB |
| testing-conventions | 1.0 | 2026-03-12 | 23 | 340 KB |

### Absorbed Drops (in this project)
| Name | Version | Absorbed On | Entries |
|------|---------|------------|---------|
| payments-domain | 2.1 | 2026-03-14 | 89 |

*Export a new drop: `/xgh-drop` | Import: `/xgh-absorb <path>`*
```

### 4.4 Output Style Guide

Context Drops output follows the xgh convention: scannable, emoji-accented, table-structured.

**Principles:**
- **Preview before action:** Both export and import show a summary before proceeding. No silent bulk operations.
- **Provenance is visible:** Every import summary shows where knowledge came from. Every listing shows absorbed drops.
- **Sizes and counts are prominent:** Developers want to know how much data is moving. Show entry counts and file sizes consistently.
- **PII transparency:** Export always reports what was redacted. Zero-tolerance for silent data leaks.

**Visual elements:**

| Element | Purpose |
|---------|---------|
| `## 🐴🤖 xgh drop/absorb/drops` | Consistent header per command |
| Source/Contents tables | Structured overview of what is being exported/imported |
| PII Filtering table | Transparency on what was redacted |
| Compatibility checks | Trust-building: show that the drop was verified before import |
| Status emojis (checkmark/warning/cross) | Quick scan of compatibility and conflict status |
| Provenance tags in summaries | Always show `source_drop` so the user knows where knowledge originated |
| Italicized next-step hints | Actionable follow-up after each operation |

### 4.5 Edge Cases

#### Empty Scope (No Matching Content)

**Behavior:** If the requested scope matches zero context tree files, zero vectors, and zero reasoning chains, the compiler reports this clearly and does not create an empty drop.

```markdown
## 🐴🤖 xgh drop

No content matched the scope "quantum-computing patterns".

**Suggestions:**
- Broaden the scope: `/xgh-drop --scope all`
- Check available topics: `/xgh-ask "what topics exist in memory?"`
```

#### Absorbing the Same Drop Twice

**Behavior (P0):** Duplicate entries are created with the same `source_drop` tag. The user can purge duplicates with `/xgh-absorb --rollback <name>` and re-absorb.

**Behavior (P1, with versioning):** If the version matches, skip with a message: "swift-architecture v1.0 is already absorbed. Use `--force` to re-import." If the version is newer, update in place.

#### Incompatible Embedding Model

**Behavior:** The hydrator detects model mismatch from the manifest. It re-embeds all vectors from the `text` field using the local model. This is slower but produces compatible vectors.

```markdown
### Compatibility
| Check | Status |
|-------|--------|
| Embedding model match | ⚠️ Mismatch (drop: text-embedding-ada-002, local: ModernBERT) |
| | Re-embedding 47 vectors from source text... |
```

The re-embedding adds latency (estimated 1-2s per 100 vectors) but is fully automatic.

#### Corrupted or Invalid Manifest

**Behavior:** Import aborts with a clear error. No partial import occurs.

```markdown
## 🐴🤖 xgh absorb

❌ Invalid drop: manifest.json failed validation.

**Error:** Missing required field: `embedding_model`
**Path:** /path/to/broken.drop/manifest.json

*This drop may have been created with an older xgh version. Ask the author to re-export.*
```

#### Very Large Drop (>50MB)

**Behavior:** The hydrator warns before proceeding:

```markdown
⚠️ This drop is 78 MB (1,247 vectors, 89 context tree files, 34 reasoning chains).
Import may take 2-3 minutes. Proceed? (Y/n)
```

---

## 5. Technical Boundaries

### 5.1 Drop File Format

A `.drop` is a directory containing:

```
<name>.drop/
  manifest.json          # Required: metadata, schema version, content hash
  context-tree/          # Optional: subset of .xgh/context-tree/ markdown files
  vectors.jsonl          # Optional: Cipher vectors (embeddings + source text + metadata)
  reasoning-chains/      # Optional: serialized reasoning memories (one JSON per chain)
  README.md              # Required: human-readable summary
```

**Manifest schema (`config/drop-manifest.schema.json`):**

```json
{
  "schema_version": 1,
  "name": "swift-architecture",
  "version": "1.0",
  "author": "Sofia",
  "created_at": "2026-03-10T14:32:00Z",
  "source_project": "swift-payments",
  "scope_description": "Architecture patterns, naming conventions, test structure",
  "scope_tags": ["architecture", "patterns", "naming", "testing"],
  "embedding_model": "ModernBERT",
  "xgh_version": "1.0.0",
  "content_hash": "sha256:abc123...",
  "counts": {
    "context_tree_files": 12,
    "vectors": 47,
    "reasoning_chains": 8
  },
  "dependencies": [],
  "pii_filtered": true,
  "pii_redaction_count": 3
}
```

### 5.2 Storage

| Data | Location | Retention |
|------|----------|-----------|
| Exported drops | `.drops/<name>.drop/` (local, git-committable) | Permanent until manually deleted |
| Imported context tree files | `.xgh/context-tree/` (merged into existing tree) | Follows context tree retention (permanent, git-committed) |
| Imported vectors | Cipher / Qdrant (via `cipher_store_reasoning_memory`) | Follows Cipher retention policy |
| Imported reasoning chains | Cipher / Qdrant | Follows Cipher retention policy |
| Drop config | `.xgh/config.yaml` → `modules.drops` | Permanent (config file) |
| Import log | `.xgh/drops/import-log.jsonl` (append-only) | 90 days, max 5MB |

### 5.3 Size Budgets

| Component | Budget | Rationale |
|-----------|--------|-----------|
| Single context tree file in drop | <100KB | Markdown knowledge files should be concise. Larger files indicate insufficient curation. |
| `vectors.jsonl` per drop | <50MB | ~500 vectors at ~100KB each (768-dim float32 + metadata + source text). Covers a large project's full scope. |
| `reasoning-chains/` per drop | <10MB | ~100 reasoning chains at ~100KB each. Reasoning chains are structured summaries, not full conversations. |
| Total drop bundle (typical) | <5MB | Scoped export of a mature project. Covers 90% of use cases. |
| Total drop bundle (maximum) | <100MB | Full-project export with extensive vector history. Warning shown at >50MB. |
| `manifest.json` | <10KB | Metadata only. |
| `README.md` | <50KB | Auto-generated summary. |

### 5.4 Performance Budget

| Operation | Budget | Method |
|-----------|--------|--------|
| **Scoped export (P0)** | <30s | Cipher query (~2s) + context tree scan (~500ms) + PII filter (~5s) + write (~1s) |
| **Full project export** | <2min | Larger Cipher query + full context tree + PII filter on all content |
| **Import (same model)** | <15s | Manifest validation (~100ms) + context tree merge (~2s) + vector injection (~10s) + provenance tagging (~1s) |
| **Import (model mismatch, re-embed)** | <60s | Same as above + re-embedding (~1-2s per 100 vectors) |
| **PII filter per file** | <500ms | Regex-based scanning. No external API calls. |
| **Manifest validation** | <100ms | JSON schema validation. Local only. |
| **Drop listing scan** | <1s | Directory glob + manifest reads |

### 5.5 Privacy & PII Filtering

**Default PII filters (always active):**

| Pattern | Type | Example Redacted |
|---------|------|-----------------|
| Email addresses | Regex | `user@company.com` → `[REDACTED-EMAIL]` |
| Slack handles | Regex | `@pedro`, `<@U12345>` → `[REDACTED-SLACK]` |
| Internal URLs | Regex | `*.internal.*`, `*.corp.*`, `*.local.*` → `[REDACTED-URL]` |
| IP addresses | Regex | `192.168.1.1` → `[REDACTED-IP]` |
| API keys/tokens | Regex | `sk-...`, `ghp_...`, `xoxb-...` → `[REDACTED-KEY]` |
| AWS credentials | Regex | `AKIA...` → `[REDACTED-KEY]` |

**Custom filters:**

Enterprise teams can add custom scrubbers in `.xgh/config.yaml`:

```yaml
modules:
  drops:
    pii_filters:
      - pattern: "PTECH-\\d+"
        replacement: "[REDACTED-TICKET]"
      - pattern: "https://mycompany\\.atlassian\\.net/.*"
        replacement: "[REDACTED-JIRA-URL]"
```

**Privacy contract:** A drop should be safe to publish to a public git repository. The PII filter is the last gate before the bundle is written. If a PII item slips through, the provenance tag enables tracking which drops to recall.

---

## 6. Hooks & Skills Integration

### 6.1 Existing Hooks

xgh currently ships 4 hooks. Here is every hook, what it does today, and how Context Drops interacts with it.

#### `xgh-session-start.sh` (SessionStart) — **Consumed**

**What it does today:** Loads top 5 context tree files by score, injects decision table, optionally triggers `/xgh-brief`.

**Context Drops integration:** Context Drops **consumes** this hook's output. When a drop has been absorbed, the imported context tree files are scored and loaded by the existing SessionStart logic alongside native context tree files. No modification to the hook is needed — imported files are regular context tree markdown files with standard frontmatter plus an additional `source_drop` field. The hook's existing scoring system (maturity_rank * 100 + importance) works transparently with absorbed content.

**Interaction type:** Consume (no hook changes required).

#### `xgh-prompt-submit.sh` (UserPromptSubmit) — **No change**

**What it does today:** Detects code-change intent via regex, injects Cipher tool hints (memory search, extract, store).

**Context Drops integration:** Context Drops does **not** interact with this hook. Drop export and import are explicit, user-initiated operations (`/xgh-drop`, `/xgh-absorb`) — not triggered by prompt intent detection. The existing tool hints (cipher_memory_search, cipher_store_reasoning_memory) naturally surface absorbed drop knowledge when the developer asks code-change questions, because absorbed vectors and context tree files are indistinguishable from native ones in Cipher queries.

**Interaction type:** None (operates independently).

#### `cipher-pre-hook.sh` (PreToolUse) — **No change**

**What it does today:** Fires before `cipher_extract_and_operate_memory` and `cipher_workspace_store`. Detects complex content (markdown, tables, code blocks, >500 chars) that Cipher's 3B extraction model will likely reject. Warns the agent to use direct Qdrant storage instead.

**Context Drops integration:** Context Drops does **not** interact with this hook. The drop compiler and hydrator do not use Cipher's extraction endpoint — they use direct vector injection (same path as `workspace-write.js`). The pre-hook's warnings about complex content are irrelevant to drop operations because drops bypass the 3B extraction model entirely.

**Interaction type:** None (operates independently).

#### `cipher-post-hook.sh` (PostToolUse) — **Indirect benefit**

**What it does today:** Fires after `cipher_extract_and_operate_memory` and `cipher_workspace_store`. Detects `extracted: 0` failures and instructs the agent to retry via direct Qdrant storage.

**Context Drops integration:** Context Drops benefits **indirectly**. If a developer manually curates knowledge after absorbing a drop (e.g., refining an absorbed pattern), and that curation goes through Cipher's extraction endpoint, the post-hook ensures the refined knowledge is stored even if the 3B model rejects it. This is the same benefit any Cipher write operation gets — not specific to Context Drops.

**Interaction type:** Indirect benefit (no hook changes required).

### 6.2 Skills Integration

Skills that naturally interact with Context Drops — either as export triggers, import consumers, or complementary workflows.

| Skill | Drops Role | How |
|-------|-----------|-----|
| **`/xgh-brief`** | **Import consumer.** | When a drop has been recently absorbed (within the last session), `/xgh-brief` can note: "New knowledge source: swift-architecture v1.0 absorbed today (67 entries)." This helps the developer (or a reviewer) understand why the agent suddenly "knows" things it did not know before. The brief skill queries the import log for recent absorptions. |
| **`/xgh-ask`** | **Import consumer.** | After absorbing a drop, `/xgh-ask` queries naturally surface absorbed knowledge alongside native knowledge. The provenance tag enables the agent to attribute answers: "Based on a pattern from `swift-architecture v1.0` (absorbed drop)..." No skill changes required — Cipher search is model-agnostic about knowledge source. |
| **`/xgh-curate`** | **Export trigger / Refinement.** | After absorbing a drop, the developer may want to refine or extend the imported knowledge. `/xgh-curate` writes refined knowledge to the context tree and Cipher, which can then be re-exported in a future `/xgh-drop`. The curate-then-drop cycle is how knowledge evolves across projects: absorb → use → refine → re-export. |
| **`/xgh-status`** | **Health display.** | `/xgh-status` adds a Context Drops section: number of exported drops, number of absorbed drops, total absorbed entries, import log size, last export/absorb timestamp. Helps the developer track their knowledge portfolio. |
| **`/xgh-index`** | **Complementary.** | `/xgh-index` extracts architecture from code; `/xgh-drop` exports curated knowledge from memory. They produce different types of knowledge: index captures what the code *is*, drops capture what the team *decided and why*. A comprehensive onboarding bundle might combine both: first `/xgh-index` the repo, then `/xgh-absorb` the team's domain drops. |
| **`/xgh-track`** | **No interaction.** | `/xgh-track` manages ingest pipeline sources (Slack, Jira, GitHub). Drops are not an ingest source — they are a manual, curated export/import mechanism. A future P2 feature (CI-generated drops) could bridge the two, but v1 keeps them separate. |
| **`/xgh-help`** | **Contextual hint.** | `/xgh-help` adds Context Drops commands to the command reference. If the project has no absorbed drops and the context tree is thin, help suggests: "Have drops from another project? Run `/xgh-absorb <path>` to import team knowledge." If the project has rich context, help suggests: "Share your knowledge: `/xgh-drop` exports a portable bundle." |

### 6.3 New Components Summary

| Component | Type | File | Hook/Event |
|-----------|------|------|------------|
| Drop Compiler skill | skill | `skills/drop-compiler/drop-compiler.md` | N/A (invoked by command) |
| Drop Hydrator skill | skill | `skills/drop-hydrator/drop-hydrator.md` | N/A (invoked by command) |
| `/xgh-drop` command | command | `commands/drop.md` | N/A (user-initiated) |
| `/xgh-absorb` command | command | `commands/absorb.md` | N/A (user-initiated) |
| `/xgh-drops` command | command | `commands/drops.md` | N/A (user-initiated) |
| Manifest schema | configFile | `config/drop-manifest.schema.json` | N/A (validation) |

**No new hooks are required.** Context Drops is entirely command-driven. Unlike Momentum (which needs SessionEnd capture), drops are explicit user actions that do not require automatic triggers.

---

## 7. Non-Goals

Context Drops is a knowledge portability layer. These are things it explicitly does NOT do:

| Non-Goal | Why Not | Related Feature |
|----------|---------|-----------------|
| **Real-time sync between projects** | Drops are snapshots, not live mirrors. Real-time sync is the Memory Mesh idea (separate proposal). | Memory Mesh (collaboration.md, Idea 1) |
| **Automatic export on commit/release** | P0/P1 drops are manually curated. Automatic CI drops are a P2 feature. Manual curation ensures quality. | CD-P2-02 (CI-generated drops) |
| **Code or file content export** | Drops export *knowledge about code* (patterns, decisions, reasoning), not the code itself. Code lives in git. | git, repos |
| **Dependency management** | Drops are not packages. There is no lockfile, no dependency resolution beyond basic composite drops (P1). | npm, package managers |
| **Access control or permissions** | P0/P1 drops are files — whoever has the file can absorb it. Access control is a registry feature (P2). | CD-P2-01 (Drop registry) |
| **Conversation replay or session history** | Drops export distilled knowledge, not raw conversations. Session history is a different feature. | Momentum PRD, Session Replay |
| **Ingest pipeline integration** | Drops are manually curated bundles. They do not replace or feed into the ingest pipeline (Slack/Jira/GitHub). | `/xgh-retrieve`, `/xgh-analyze` |
| **Cross-machine sync** | Drops are portable files. They travel via git, URL, or filesystem — not via a sync protocol. | Cipher MCP (already cross-machine for vector memory) |
| **Merging or diffing code** | Drops merge *knowledge* (context tree files, vectors), not code. Conflict resolution is at the knowledge level, not the code level. | git merge |
| **Quality scoring of imported knowledge** | P0 imports everything in the drop. Quality curation happens at export time (the author decides what to include). Automated quality scoring is a future possibility. | CD-P2-06 (Drop analytics) |

**What Context Drops enables but does not implement:**

- **Drop Marketplace** — Drops are the primitive. A marketplace for discovering and sharing them is a P2 ecosystem feature.
- **Knowledge Diffing** — The versioned manifest format supports diffing. The tooling to compute and display diffs is P2.
- **Memory Mesh** — Automatic drop exchange between linked workspaces. The mesh protocol builds on top of drops but is architecturally separate.

---

## 8. Open Questions

### 8.1 Design Decisions Needing Input

| # | Question | Options | Recommendation | Needs |
|---|----------|---------|---------------|-------|
| Q1 | **How does the drop compiler query Cipher for scoped content?** Cipher's `cipher_memory_search` is semantic — it returns results by similarity, not by exact scope boundaries. | (a) Semantic query with similarity threshold + manual curation by the agent. (b) Tag-based filtering if Cipher supports metadata filters. (c) Export everything, then let the agent prune the results before bundling. | **(a)** — Semantic query is the natural fit for xgh's dual-engine search. The agent reviews results and prunes before bundling. This keeps the human in the loop for quality. | Verify that `cipher_memory_search` returns enough metadata to filter effectively. |
| Q2 | **Should the default output path be `.drops/` (git-committable) or `.xgh/drops/` (alongside other xgh state)?** | (a) `.drops/` at project root — visible, git-committable, easy to discover. (b) `.xgh/drops/` — consistent with other xgh state. (c) Configurable, default to `.drops/`. | **(c)** — Default to `.drops/` for discoverability. Configurable via `modules.drops.default_output_path` for teams that want it elsewhere. `.drops/` is intentionally NOT in `.xgh/` because drops are meant to be shared (git, URL), unlike `.xgh/momentum/` which is local-only. | Confirm `.drops/` does not conflict with any existing convention. |
| Q3 | **Should PII filtering be mandatory or opt-out?** | (a) Always on, no opt-out. (b) On by default, opt-out with `--no-pii-filter` flag. (c) Off by default, opt-in with `--filter-pii`. | **(a)** — Always on. PII filtering is a safety mechanism, not a feature toggle. The risk of accidentally exporting PII to a public drop is too high. Custom filters can be added but the defaults cannot be disabled. | Review whether the default patterns produce false positives that would make drops unusable. |
| Q4 | **How should vector re-embedding work when models differ?** The source text in `vectors.jsonl` enables re-embedding, but this adds latency and changes the semantic space. | (a) Always re-embed if models differ (correctness over speed). (b) Import vectors as-is and mark them as "approximate" (speed over correctness). (c) Offer both: `--reembed` (default) and `--fast-import`. | **(a)** — Always re-embed. Mixed-model vector spaces produce unreliable similarity results. The latency penalty (1-2s per 100 vectors) is acceptable for a one-time import operation. | Benchmark re-embedding latency with ModernBERT and text-embedding-ada-002 at 500 vectors. |
| Q5 | **Should drops include embedding vectors at all, or only source text?** Including vectors enables zero-cost import when models match, but increases bundle size significantly. | (a) Include both vectors and source text (current design). (b) Include only source text, always re-embed on import. (c) Include vectors but make them optional (hydrator uses them if model matches, re-embeds if not). | **(c)** — Include both. When models match (the common case for teams using the same xgh setup), zero-cost import is a significant UX win. When they don't match, the source text fallback works. The size overhead (~100KB per 100 vectors for 768-dim) is acceptable given the 5MB typical budget. | Measure actual vector size for common embedding dimensions (384, 768, 1536). |

### 8.2 Technical Unknowns

| # | Unknown | Risk Level | Investigation Plan |
|---|---------|-----------|-------------------|
| T1 | **Cipher bulk vector injection.** Can vectors be injected into Qdrant efficiently in bulk (100+ vectors in one operation), or does each require a separate `cipher_store_reasoning_memory` call? | High | Test Qdrant's batch upsert API. If Cipher does not expose batch operations, use `workspace-write.js` (the direct Qdrant write helper) for bulk injection. |
| T2 | **Context tree merge conflicts at scale.** With a large drop (50+ context tree files) and a large existing tree, how often do filename conflicts occur? | Medium | Analyze naming patterns in 5 real context trees. If conflicts are rare (<5%), `keep-both` with suffix renaming is sufficient. If frequent, implement a smarter merge strategy. |
| T3 | **PII filter false positive rate.** Do the default regex patterns produce false positives that strip legitimate technical content (e.g., IP addresses in network architecture docs, email format examples in validation logic)? | Medium | Run PII filters on 10 real context trees and 100 reasoning chains. Measure false positive rate. If >5%, add allowlist support. |
| T4 | **Cross-platform path handling.** Drops may be created on macOS and absorbed on Linux (or vice versa). Do context tree paths survive cross-platform transfer? | Low | Use forward slashes in all stored paths. Test export on macOS, import on Linux. |
| T5 | **Tarball format for URL distribution.** What is the most portable tarball format for cross-platform distribution? `.tar.gz` is universal but requires `tar`. `.zip` works on Windows but is less common in CLI workflows. | Low | Support both. Detect format from file extension. |

### 8.3 Scope Boundary Questions

| # | Question | Current Answer | May Change If |
|---|----------|---------------|---------------|
| S1 | Does Context Drops replace the linked workspaces concept? | **No.** Linked workspaces are automatic, live connections between projects. Drops are manual, snapshot-based transfers. Drops are the portable primitive; linked workspaces could use drops as the transport layer. | Memory Mesh (P2) unifies both into a single protocol. |
| S2 | Should drops be versioned with semver? | **Yes (P1).** The manifest carries a `version` field. This enables update-in-place on re-absorb and the rollback command. | If versioning proves too complex, simplify to timestamp-based "latest wins" in P0. |
| S3 | Can drops contain executable code? | **No.** Drops contain markdown (context tree), JSON/JSONL (vectors, reasoning chains, manifest), and nothing else. No scripts, no hooks, no executables. This is a security boundary. | Never. This is a non-negotiable safety constraint. |
| S4 | Should Context Drops work without Cipher? | **Partially.** Context tree fragments can be exported and imported without Cipher (they are just markdown files). Vector and reasoning chain export/import require Cipher. A "context-tree-only" mode is feasible for lightweight use. | If there is demand for a Cipher-free mode, implement it as a `--context-tree-only` flag. |

---

## Appendix A: Implementation Sequence

Suggested implementation order, mapping to existing xgh development patterns:

| Phase | Scope | Components | Est. Effort |
|-------|-------|-----------|-------------|
| **Phase 1** | P0 Core (export + import) | Manifest schema (`config/drop-manifest.schema.json`), drop compiler skill (`skills/drop-compiler/drop-compiler.md`), drop hydrator skill (`skills/drop-hydrator/drop-hydrator.md`), commands (`commands/drop.md`, `commands/absorb.md`, `commands/drops.md`), PII filter implementation, `techpack.yaml` registration | 3-4 days |
| **Phase 2** | P0 Polish (edge cases, provenance, config) | Provenance tagging, conflict resolution, vector compatibility/re-embedding, config schema in `.xgh/config.yaml`, import log, tests | 2-3 days |
| **Phase 3** | P1 Enhanced (distribution, versioning) | URL-based import, git-hosted drops, selective import, drop versioning, composite drops, scope presets, dry-run preview | 3-4 days |
| **Phase 4** | P2 Extended (registry, CI, diffing) | Drop registry API, GitHub Action template, knowledge diffing, Memory Mesh bridge, marketplace | 4-5 days (deferred) |

**Total estimated effort:** 8-11 days for P0+P1. P2 is deferred until the archetype system and Memory Mesh protocol are designed.

---

## Appendix B: Archetype Installation

Context Drops is installed by default for most archetypes, since knowledge portability is a core value proposition across all use cases.

| Archetype | Installed by Default? | Rationale |
|-----------|----------------------|-----------|
| Solo Dev | Yes | Core value: transfer knowledge across personal projects. "Start every project with everything I learned from the last 5." |
| OSS Contributor | Yes | Primary collaboration channel: maintainers publish drops, contributors absorb them before contributing. |
| Enterprise | Yes | Onboarding drops and cross-team knowledge sharing are high-impact enterprise use cases. |
| OpenClaw | Optional | Useful for power users who bridge personal/professional contexts, but not core to the personal assistant use case. |

**Progressive enhancement tiers:**

| Level | Capability | Infrastructure Required |
|-------|-----------|----------------------|
| **Basic** | Export to local directory, absorb from local directory. | None. Works on day one. |
| **Git-integrated** | Drops committed to repos. `/xgh-drops --repo` discovers them. | Git (already present). |
| **URL-distributed** | Absorb from hosted tarballs. | HTTP access. |
| **Registry** (future) | Central/self-hosted drop registry with search, versioning, access control. | Registry server (P2). |

Each level works independently. Level 3 never requires level 4.

---

## Appendix C: Manifest Schema Evolution

The manifest uses `schema_version` to support forward-compatible evolution:

| Version | Additions | Breaking Changes |
|---------|-----------|-----------------|
| **v1** (P0 launch) | `schema_version`, `name`, `version`, `author`, `created_at`, `source_project`, `scope_description`, `scope_tags`, `embedding_model`, `xgh_version`, `content_hash`, `counts`, `pii_filtered`, `pii_redaction_count` | N/A (initial version) |
| **v2** (P1) | `dependencies[]`, `scope_preset`, `export_flags`, `min_xgh_version` | None — additive only |
| **v3** (P2) | `registry_url`, `published_at`, `download_count`, `signature` | None — additive only |

**Compatibility rule:** The hydrator must always be able to read manifests from older schema versions. Unknown fields are ignored. Missing fields use sensible defaults.

---

## Self-Review Notes

**Engineer lens:**
- Fixed: Added explicit detail on how vector re-embedding works (Q4/Q5) and the bulk injection unknown (T1) -- these are the highest-risk technical areas.
- Fixed: Clarified that drop compiler uses direct Qdrant injection (workspace-write.js path), not Cipher's extraction endpoint, which is why PreToolUse/PostToolUse hooks are not involved.
- Fixed: Added S3 (no executable code in drops) as a non-negotiable security boundary.
- Fixed: Added CD-P0-14 for config integration (was missing from initial draft).

**PM lens:**
- Fixed: Added concrete persona names and scenarios matching the Momentum PRD style (Sofia, Jordan, Marcus, Sam) instead of generic descriptions.
- Fixed: Success metrics now include measurement methods for every metric, not just targets.
- Fixed: Added "What Context Drops enables but does not implement" section to Non-Goals for forward-looking clarity.

**Designer lens:**
- Fixed: Export and import UX flows now show full example output including PII transparency, compatibility checks, and provenance tags.
- Fixed: Added edge case for empty scope, duplicate import, corrupted manifest, and large drops.
- Fixed: Output style guide includes the principle "preview before action" -- both export and import show summaries before proceeding.

*This PRD is a living document. Update it as design decisions from Section 8 are resolved.*
