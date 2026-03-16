# xgh Skills & Hooks Audit

**Date:** 2026-03-16
**Auditor:** Claude Opus 4.6
**Scope:** All hooks (2) and skills (29) in the xgh repository

---

## Section 1: Duplications

### 1.1 `brief/brief.md` vs `briefing/briefing.md` — FULL DUPLICATE

These are two separate skills that do **the same thing**: session briefing with Slack/Jira/GitHub data gathering, classification into NEEDS YOU NOW / IN PROGRESS / INCOMING / TEAM PULSE / TODAY sections, and a SUGGESTED FOCUS.

`brief/brief.md` (line 1):
```
name: xgh:briefing
description: >
  Morning/session briefing skill. Checks Slack, Jira, and GitHub...
```

`briefing/briefing.md` (line 1):
```
name: xgh:briefing
description: Intelligent session briefing. Aggregates Slack, Jira, GitHub, Gmail, Calendar, Figma...
```

Both even use `name: xgh:briefing`. The `briefing/` version is strictly more capable (adds Gmail, Calendar, Figma, compact mode, focus mode, pre-meeting mode, scoring engine).

**Recommendation:** Delete `brief/brief.md` entirely. Keep `briefing/briefing.md` as the canonical briefing skill.

---

### 1.2 `collab/collab.md` vs `agent-collaboration/instructions.md` — NEAR-FULL DUPLICATE

Both define the same message protocol, same YAML fields, same status transitions, same workflow participation instructions. The `collab/` version is a superset (adds Security Reviewer role, Agent Registry, Workflow Templates sections, more detailed rules).

`agent-collaboration/instructions.md` line 16-25 and `collab/collab.md` line 16-25 are **verbatim identical** — the entire Message Protocol section, Message Types table, and Status Transitions block.

**Recommendation:** Delete `agent-collaboration/instructions.md`. Keep `collab/collab.md` as the canonical collaboration skill.

---

### 1.3 `continuous-learning/continuous-learning.md` vs `prompt-submit.sh` hook — HEAVY OVERLAP

The `continuous-learning` skill defines the "iron law" of memory search before code and curate after code. The `prompt-submit.sh` hook **already injects this exact protocol** on every code-change prompt, including:
- The same decision table (when to search, when to store)
- The same workflow (`Code task received -> cipher_memory_search FIRST -> Work -> cipher_extract_and_operate_memory -> Done`)
- The same Quick Reference table

The hook runs automatically. The skill is a longer version of the same instructions that an agent would need to explicitly invoke.

**Recommendation:** Merge unique content from `continuous-learning` (the Rationalization Table and Hard Gates) into a leaner skill or into the hook's injected context. The current duplication means the agent sees the same instructions twice in every code session.

---

### 1.4 `convention-guardian/convention-guardian.md` vs `continuous-learning/continuous-learning.md` — PARTIAL OVERLAP

Both have "Iron Law" preambles about checking conventions/memory before writing code. Both have Rationalization Tables with overlapping entries (e.g., "I already know the standard patterns" vs "I already know the conventions from my training data"). Both instruct the agent to call `cipher_memory_search` before coding.

**Recommendation:** Extract the shared "check before you code" protocol into a single reference. Have convention-guardian focus exclusively on convention storage format and evolution, not the "when to query" instructions already covered by the hook and continuous-learning.

---

### 1.5 MCP Auto-Detection boilerplate — COPIED ACROSS 4 SKILLS

`design/design.md`, `implement/implement.md`, `investigate/investigate.md`, and `init/init.md` all contain nearly identical "MCP Auto-Detection" sections with:
- The same detection procedure (check tool availability)
- The same graceful degradation pattern
- The same "First-use detection pattern" (5 identical steps)
- The same output format (`Available integrations: [x] ... [ ] ...`)

**Recommendation:** Extract shared MCP detection into `mcp-setup/mcp-setup.md` (it already has the detection protocol) and have workflow skills reference it: "Run the detection protocol from xgh:mcp-setup" instead of duplicating 30+ lines each.

---

### 1.6 `memory-verification/memory-verification.md` vs `curate/curate.md` Step 4 — PARTIAL OVERLAP

`curate/curate.md` already includes verification in its Quality Checklist:
```
- [ ] Verification: cipher_memory_search finds the new entry
```

`memory-verification` expands this into a full skill with detailed failure modes. However, the core instruction (search after store to verify) appears in both places.

**Recommendation:** Keep `memory-verification` as the detailed reference but remove the verification checklist items from `curate` and replace with "Run the xgh:memory-verification protocol".

---

## Section 2: Inconsistencies

### 2.1 Maturity demotion thresholds differ

`README.md` line 160-164:
```
| core      | importance >= 85 | importance < 25 |
| validated | importance >= 65 | importance < 30 |
```

`context-tree-maintenance.md` line 79-81:
```
| core -> validated | importance < 50 (i.e., 85 - 35 = 50) |
| validated -> draft | importance < 30 (i.e., 65 - 35 = 30) |
```

Core demotion threshold: README says `<25`, context-tree-maintenance says `<50`. These contradict each other.

**Fix:** Align README to match context-tree-maintenance (which has the detailed hysteresis math). The maintenance file's values (50 and 30) are the intended ones; README's values (25 and 30) appear to be from an earlier draft.

---

### 2.2 `brief/brief.md` has wrong `name` field

`brief/brief.md` line 2: `name: xgh:briefing` (should be `xgh:brief` to match its directory, or should not exist at all — see duplication finding).

---

### 2.3 `/xgh-briefing` vs `/xgh-brief` command name confusion

README line 122: `/xgh-briefing` — "Session briefing"
CLAUDE.md line 21: `/xgh-brief` — "session briefing"
`brief/brief.md`: triggered by `/xgh-brief`
`briefing/briefing.md`: triggered by `/xgh-briefing`

Two different commands point to two different skills doing the same thing.

**Fix:** Pick one command name. Since the README and `briefing/` skill both use `/xgh-briefing`, drop `/xgh-brief` and the `brief/` skill entirely.

---

### 2.4 `init/init.md` requires Slack MCP as critical, but the project is solo-dev

`init/init.md` line 13-14 lists Slack MCP as a **required** dependency:
```
required:
  - slack: "Slack MCP - channel access (slack_read_channel)"
```

For a solo developer (or anyone without Slack), this is a hard blocker. The skill says "stop and tell the user" if Slack isn't configured (line 57-59). But xgh should work without Slack.

**Fix:** Move Slack to optional. Cipher is the only true hard requirement.

---

### 2.5 `session-start.sh` decision table is a pale shadow of `prompt-submit.sh`

`session-start.sh` injects 3 simple bullet points:
```python
decision_table = [
    "Before writing code: run cipher_memory_search first.",
    "After significant work: run cipher_extract_and_operate_memory.",
    "For architectural choices: store rationale with cipher_store_reasoning_memory."
]
```

`prompt-submit.sh` injects a full 80-line decision table with rationalization tables, workflow diagrams, and hard rules. The session-start version is so brief it adds almost no value over what the prompt-submit hook already provides every time.

**Fix:** Either enrich session-start's decision table or remove it (the prompt-submit hook covers it on every code prompt anyway).

---

### 2.6 Scoring formula inconsistency

`ask/ask.md` line 140-141:
```
score = (0.5 * cipher_similarity + 0.3 * bm25_score + 0.1 * importance + 0.1 * recency) * maturityBoost
```

`cross-team-pollinator.md` line 103:
```
score = (0.5 * relevance_score + 0.3 * maturity_boost + 0.2 * recency)
```

`README.md` line 260:
```
score = (0.5 * cipher + 0.3 * bm25 + 0.1 * importance/100 + 0.1 * recency) * maturityBoost
```

The cross-team-pollinator uses a completely different formula (no importance, different weights, maturity as a weight instead of a multiplier).

**Fix:** Standardize on one formula. Use README's as canonical and update cross-team-pollinator.

---

### 2.7 Tool name inconsistency: `slack_read_channel` vs `slack_search_public`

Skills use different Slack tool names inconsistently:
- `init/init.md`: `slack_read_channel`, `slack_search_channels`
- `investigate/investigate.md`: `slack_read_thread`, `slack_search_public`, `slack_search_public_and_private`
- `briefing/briefing.md`: `slack_search_public_and_private`, `slack_list_channels`
- `retrieve/retrieve.md`: `slack_read_channel`

These names should match the actual MCP tool names. Some may be wrong.

**Fix:** Audit actual Slack MCP tool names from the `@anthropic/mcp-slack` package and standardize across all skills.

---

### 2.8 References to `~/.xgh/ingest.yaml` assume ingest pipeline

Many skills (`retrieve`, `analyze`, `doctor`, `calibrate`, `track`, `init`, `profile`, `index`) reference `~/.xgh/ingest.yaml`, `~/.xgh/inbox/`, `~/.xgh/logs/`, and `~/.xgh/lib/` directories. These assume an ingest pipeline infrastructure that does not appear to be part of the installed product — the installer creates files in `.claude/` and `.xgh/context-tree/`, not a `~/.xgh/` global directory.

**Fix:** Clarify whether the ingest pipeline is implemented. If not, these skills reference non-existent infrastructure.

---

## Section 3: Value Assessment

| Skill | Value | Reason | Recommendation |
|-------|-------|--------|----------------|
| `ask` | **High** | Genuinely useful query routing tiers, refinement patterns, and stop conditions. Teaches agents to search effectively. | Keep |
| `curate` | **High** | Structured knowledge format, domain/topic hierarchy, quality checklist. Essential for knowledge quality. | Keep |
| `implement` | **High** | Best skill in the pack. Comprehensive ticket-to-PR workflow with cross-platform context, interactive interview, design proposal, TDD plan. Real workflow value. | Keep |
| `investigate` | **High** | Systematic debugging methodology with hypothesis formation, hard gate after 3 failures, structured report. Prevents shotgun debugging. | Keep |
| `design` | **High** | Deep Figma mining, component mapping, token mapping, interactive state review. Unique value for UI work. | Keep |
| `mcp-setup` | **High** | Practical zero-friction MCP configuration. Solves a real pain point. | Keep |
| `briefing` | **Medium** | Useful session start overview, but depends heavily on having Slack/Jira/GitHub MCPs configured. Without MCPs it's just "What would you like to work on?" | Keep (delete duplicate `brief/`) |
| `collab` | **Medium** | Defines a message protocol for multi-agent workflows. Useful if you actually have multiple agents. For solo devs, theoretical. | Keep (delete duplicate `agent-collaboration/`) |
| `track` | **Medium** | Interactive project onboarding. Useful for ingest pipeline users. | Keep if ingest pipeline is real |
| `doctor` | **Medium** | Pipeline health check. Only valuable if the ingest pipeline is running. | Keep if ingest pipeline is real |
| `init` | **Medium** | First-run wizard. Orchestrates other skills well. | Keep, but fix Slack requirement |
| `index` | **Medium** | Codebase architecture extraction into Cipher. Useful for large repos. | Keep |
| `profile` | **Medium** | Engineer throughput analysis from Jira. Niche but specific and well-defined. | Keep |
| `retrieve` | **Medium** | Headless Slack retrieval loop. Only valuable if the full ingest pipeline is deployed. | Keep if ingest pipeline is real |
| `analyze` | **Medium** | Headless inbox analysis loop. Same caveat as retrieve. | Keep if ingest pipeline is real |
| `calibrate` | **Low / consider removing** | Calibrates dedup threshold for the analyze skill. Extremely niche — useful maybe once. | Merge into analyze as a sub-mode |
| `context-tree-maintenance` | **Low / consider removing** | Defines scoring rules, maturity lifecycle, archival. This is reference documentation disguised as a skill. No agent would invoke this — it's rules for `context-tree.sh` to follow. | Convert to docs, not a skill |
| `continuous-learning` | **Low / consider removing** | 80% duplicated by the prompt-submit hook that runs automatically. The unique content (Rationalization Table, Hard Gates) could be merged into the hook or curate skill. | Merge into hook or remove |
| `convention-guardian` | **Low / consider removing** | Tells agents to search for conventions before coding. The hook already does this. The convention storage format is useful but could be in docs. | Merge storage format into curate, remove rest |
| `memory-verification` | **Low / consider removing** | "Search after you store" — a simple instruction inflated into a full skill. Could be 5 lines in the curate skill. | Merge into curate |
| `knowledge-handoff` | **Low / consider removing** | Theoretically generates merge summaries. No mechanism to trigger it automatically. The handoff format is useful but the skill assumes Cipher features (thread queries, file-level filtering) that may not exist. | Keep as aspirational, mark as draft |
| `pr-context-bridge` | **Low / consider removing** | Auto-curates PR reasoning to Cipher. Interesting concept but no automation trigger — relies on agents voluntarily running it throughout development. In practice, agents won't. | Keep as aspirational, mark as draft |
| `cross-team-pollinator` | **Low / consider removing** | Assumes multiple teams with separate Cipher workspaces and an `org` scope. No evidence this infrastructure exists. For solo devs: zero value. | Remove or hide behind a team flag |
| `onboarding-accelerator` | **Low / consider removing** | Queries Cipher for 5 categories of team knowledge for new developers. Duplicates what briefing + ask already do. For solo devs: no value. | Remove or mark team-only |
| `subagent-pair-programming` | **Low / consider removing** | Requires Claude Code subagent dispatching which is not a standard feature. The TDD-via-separation concept is interesting but impractical — agents cannot currently spawn isolated subagents with restricted tool access. | Remove until subagents are real |
| `todo-killer` | **Low / consider removing** | Find and fix TODOs. Any capable agent can do `grep -rn TODO` and fix them without a 175-line skill definition. The `patterns.yaml` integration adds some value but references infrastructure that may not exist. | Simplify to 30 lines or remove |
| `brief` | **Remove** | Full duplicate of `briefing` (less capable version). | Delete |
| `agent-collaboration` | **Remove** | Full duplicate of `collab` (less capable version). | Delete |

---

## Section 4: Priority Action List

### 1. Delete full duplicates (immediate, zero risk)
- Delete `skills/brief/brief.md` (duplicate of `briefing/briefing.md`)
- Delete `skills/agent-collaboration/instructions.md` (duplicate of `collab/collab.md`)
- Remove `/xgh-brief` command if it exists separately from `/xgh-briefing`

### 2. Fix maturity demotion thresholds in README
- Change README line 163 core demotion from `< 25` to `< 50` to match `context-tree-maintenance.md`

### 3. Extract shared MCP detection boilerplate
- Create a canonical MCP detection section in `mcp-setup/mcp-setup.md`
- Replace the 30+ line detection blocks in `design`, `implement`, `investigate`, and `init` with a reference to it

### 4. Merge `continuous-learning` and `convention-guardian` into the hook + curate
- Move the Rationalization Table and Hard Gates into the prompt-submit hook's injected context (or a dedicated "philosophy" doc)
- Move convention storage format from `convention-guardian` into `curate`
- Delete both skills as standalone

### 5. Fix `init/init.md` Slack hard requirement
- Move Slack from `required` to `optional` MCP dependencies
- Cipher should be the only hard requirement

### 6. Remove or quarantine team-only skills for solo use
- `cross-team-pollinator`, `onboarding-accelerator`, `subagent-pair-programming` add noise for solo developers
- Either gate them behind a `XGH_TEAM_SIZE` check or move to a `skills/team/` subdirectory that's only installed when `XGH_TEAM` is set

### 7. Convert reference-doc skills to actual docs
- `context-tree-maintenance` defines rules, not a workflow — move to `docs/context-tree-rules.md`
- `memory-verification` is a checklist — merge into `curate` skill as a final section

### 8. Standardize Slack tool names across all skills
- Audit `@anthropic/mcp-slack` package for actual tool names
- Find-and-replace across all skills

### 9. Clarify ingest pipeline status
- 8 skills reference `~/.xgh/ingest.yaml` and related infrastructure
- Either implement the pipeline or mark these skills as "requires ingest pipeline (not yet available)"

### 10. Simplify `todo-killer` and `calibrate`
- `todo-killer`: reduce to 30-40 lines, drop `patterns.yaml` integration
- `calibrate`: merge into `analyze` as a `--calibrate` flag, not a standalone skill
