# FOR Agent — Evaluation 1: Declarative Preferences with Explicit Convergence

## Role
Persistent advocate for the "Declarative Preferences with Explicit Convergence" design.
Evaluating the full design as specified in the session prompt.

---

## 1. Strongest Aspects

### A. No auto-write is the right call — and it's also the hardest call
The single most important decision in this design is that **no hook ever writes to project.yaml**. This is correct because project.yaml is a checked-in artifact. A hook that silently mutates it mid-session is a foot-gun: it creates confusing git diffs, can stomp parallel-agent writes (a documented pitfall in this codebase's memory), and breaks the auditability promise that makes declarative config worth having at all. The AGAINST agent will try to argue this creates friction. It doesn't — it creates trust. Users will commit their preferences precisely because they know hooks won't surprise them with dirty working-tree files.

### B. No session cache is the right call for this project
The design explicitly rejects session caching. The challenge document (GLM-4.7) attacks this decision by citing cumulative latency. The attack is wrong for this specific codebase: yq parses a 3ms YAML file, not a network resource. The real bottleneck the challenge correctly identifies is `_pref_probe_local()` — the auto-detect probe. But that is **already bounded** by the cascade: probe only fires if CLI + branch + default all miss. In normal operation (a filled-out project.yaml) the probe never runs. Dropping the cache eliminates an entire class of stale-data bugs that the challenge document enumerates accurately (stale after git checkout, parallel worktrees, corrupted cache) — and adds zero observable latency in the common case.

### C. Staging area pattern is well-scoped
The `.xgh/pending-preferences-<session-id>.yaml` design is elegant: session-scoped, gitignored, written only on Claude's confirmed intent (not raw regex detection), and consumed only by an explicit `/xgh-save-preferences` command. This is exactly the "explicit apply" that the challenge document's section 4 recommends as the "better alternative." The design arrived at the correct conclusion independently and built the full mechanism around it.

### D. Hook ordering discipline
Running preference hooks LAST in SessionStart and FIRST in PreToolUse is non-obvious but correct. In SessionStart, existing hooks (staleness checks, agent roster injection) should run first so their output can be included in the same additionalContext block that preferences inject. In PreToolUse, preferences must validate before context enrichment fires — you cannot enrich a blocked tool call. This ordering preserves correctness while keeping coexistence with existing hooks clean.

### E. PostCompact re-injection closes the amnesia loop
Compaction is the highest-risk moment for preference loss. Re-reading project.yaml and re-resolving for the CURRENT branch (not a stale snapshot) at PostCompact is exactly right. The design adds branch-awareness here: after a `git checkout` mid-session, the post-compact re-read will pick up the new branch context. This is a concrete improvement over any approach that caches at SessionStart and never updates.

---

## 2. Weakest Aspect — Single Biggest Risk

**The UserPromptSubmit hook's regex-to-staging-area path has an unresolved ambiguity: what counts as a confirmed preference statement?**

The design says: "Only Claude's confirmed intent writes [to the staging area]." But the UserPromptSubmit hook fires BEFORE Claude responds. It detects preference-setting patterns via regex, then injects additionalContext asking Claude to confirm. This is the right direction — but the staging area write is triggered by the hook detecting regex matches, not by Claude's response. If the hook writes to pending-preferences on detection (not on Claude's confirmation), the staging area will accumulate false positives from casual conversation ("I always use squash for cleanup PRs" — a one-time statement, not a preference update).

If the hook does NOT write until Claude confirms, then the pipeline needs a mechanism for Claude's confirmation to write to disk — which means Claude must have a write path into the staging area (a skill call, a tool use) that the hook can observe. This path is not specified.

This is the design's only genuine gap. Everything else is either correctly resolved or has a clear resolution path.

---

## 3. What the AGAINST Agent Will Attack — Top 3 Objections

### Attack 1: "11 domains × fixed cascades = combinatorial maintenance burden"
The challenge document hits this under "cascade complexity." The objection will be: as the system grows from 11 domains to 15+, each new domain requires a new loader function with its own hard-coded cascade. The design will accumulate domain-specific functions that diverge over time.

**Preemption:** The design already acknowledged this and chose domain-specific loaders deliberately. The alternative — a generic reconciler with self-declared cascade metadata — introduces inconsistent cascade definitions (as the challenge correctly shows with the dispatch/PR example). Fixed cascades are not a burden; they are a contract. The two templates (simple, branch-aware) cover 95% of domains. Adding a new domain means copying 10 lines, not designing a new protocol.

### Attack 2: "Without a cache, hooks in high-frequency paths (PreToolUse) add latency on every tool call"
The AGAINST agent will cite the challenge's performance math: if PreToolUse fires on every Bash/Edit/Write call and each call parses YAML, a session with 200 tool calls adds 200 × 3ms = 600ms of overhead.

**Preemption:** PreToolUse validation is not a full preference resolution. It reads one key (the field being validated) from an already-structured YAML file. yq's per-key lookup is sub-millisecond. The 3ms figure is for full-file parse. Even accepting 3ms per call: 600ms across a multi-hour session is below perception threshold. The AGAINST agent is conflating "every tool call touches YAML" with "every tool call fully resolves all 11 domains." It does not.

### Attack 3: "Explicit convergence (/xgh-save-preferences) is a UX cliff — users will not run it"
The objection: the staging area accumulates pending preferences that the user never promotes because running a save command requires awareness and intent. The system appears to work (Claude follows preferences in-session) but project.yaml never updates. The declarative source of truth drifts from reality.

**Preemption:** This is a real risk but it is the correct trade-off. The alternative — auto-writing on Stop — is provably dangerous (challenge section 4, parallel agents, git diff surprises). The mitigation is the Stop hook's one-shot reminder: one message per session, surfacing pending preferences and prompting the user to run `/xgh-save-preferences`. The reminder does not require any action but makes the pending state visible. Users who never promote preferences still benefit from in-session consistency. Users who promote preferences get durable config. Neither path creates data loss.

---

## 4. Strengthening Suggestions

### S1: Formalize the UserPromptSubmit confirmation protocol
Add a small convention: when the hook detects a preference-setting pattern, it injects additionalContext with a specific marker (e.g., `[XGH_PREF_CANDIDATE domain=pr field=merge_method value=squash]`). Claude is trained (via CLAUDE.md or session context) to respond to this marker by calling a thin skill — `/xgh-stage-preference domain field value` — which writes to the staging area. The hook never writes directly. This closes the ambiguity cleanly without adding complexity: the write path is a skill call, which is observable, auditable, and user-visible.

### S2: Add a PostToolUse guard for project.yaml edits
If Claude ever tries to directly edit `config/project.yaml` via a Write or Edit tool call (bypassing `/xgh-save-preferences`), PostToolUse should detect it and log a warning. This does not block the write — the user may have legitimately edited it manually — but it surfaces in the session audit trail. This is a cheap safety net that costs one grep in the PostToolUse hook.

### S3: Make the Stop hook reminder diff-aware
The current design says the Stop hook fires once per session if pending preferences exist. Strengthen this: the reminder should include a one-line summary of WHAT changed (e.g., "3 pending preferences: pr.merge_method, pr.reviewer, vcs.default_branch"), not just that something is pending. This reduces the friction of acting on the reminder: the user can decide on the spot whether the captured preferences represent their intent without having to open the staging file.

---

## Status
Evaluation 1 complete. Awaiting follow-up design sections for ongoing evaluation.
