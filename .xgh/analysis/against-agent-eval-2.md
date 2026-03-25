---
title: Against-Agent Evaluation 2 — Phased Epic Breakdown Attack
role: AGAINST (persistent skeptic)
date: 2026-03-25
prior-eval: against-agent-eval-1.md
---

# Against-Agent Evaluation 2

## Continuity from Eval 1

The three structural problems from Eval 1 remain open: branch resolution is wrong for the primary use case, conversational capture creates trust-eroding interruptions, and hook ordering is maintained by array index convention not by the framework. The phasing below inherits all three defects. Where they interact with phasing, I will name it explicitly.

---

## 1. Which Phase Will Never Ship?

**Phase 4 (Capture/Converge) will never ship as specified.**

The core mechanism is: UserPromptSubmit silently detects preference-setting intent, writes to a pending-preferences staging area, Stop hook fires a diff-aware reminder, user runs /xgh-save-preferences, orphans are cleaned up. This is five independent moving parts, each requiring the previous to work correctly.

The design adjustment says UserPromptSubmit capture is "fully silent." Eval 1 identified this as the right call. But silent detection is not the same as reliable detection. The silent path still requires Claude to read `additionalContext` from the hook, reason that a preference was being declared, write to the staging file, and suppress any conversational acknowledgment. This is an LLM as a conditional execution engine — exactly the foundational assumption that makes the pipeline fragile (Eval 1, Section 2).

The specific failure mode that kills Phase 4: the staging area (pending-preferences-`<session-id>`.yaml) is session-scoped. The design says "Stop hook reminder is diff-aware." Diff-aware means: the hook reads the staging file, computes what changed from project.yaml, and reports the delta. But the Stop hook fires when the session ends — not when the user runs /xgh-save-preferences. If the user does not run /xgh-save-preferences before the session ends, the pending file is orphaned under the old session ID. The next session starts with a new ID and cannot discover the old file without a glob over /tmp (or wherever staging files live). The design includes "orphan cleanup" but orphan cleanup requires knowing what orphans look like, when they are safe to delete, and how to surface them to the user in the next session. This is a session continuity problem that the design treats as a garbage collection problem. They are not the same problem.

Phase 4 requires solving: silent intent detection reliability, staging file persistence across session boundaries, orphan discovery and surfacing, /xgh-save-preferences conflict resolution (what if project.yaml changed since the pending was written?). Each of these is a full feature. The design describes them as bullet points under one phase. Phase 4 will be perpetually one piece away from working.

**The secondary candidate is Phase 3 (Validate/Observe).** PreToolUse validation fires on every Bash tool call. Eval 1 (Section 4) noted this runs on every `git status`, every `ls`. The design has a fast-exit guard but adds parsing overhead to every tool invocation. PostToolUse drift detection adds a second parse pass after every tool. Four hooks in one phase means four independent failure modes that all need to work simultaneously before the phase delivers value. PostToolUseFailure diagnosis is the weakest: it fires only on failures, and diagnosing a failure requires correlating what the tool attempted against what the current preference state says should have been blocked. This is stateful reasoning that depends on Phase 1 and Phase 2 both working correctly.

---

## 2. The Secretly Impossible Epic

**The "hook coexistence contract" in Phase 2 is the most underspecified and actually hardest piece in the entire design.**

The description is: "hook coexistence contract." Three words. The actual problem:

Claude Code hooks are stored as arrays in `.claude/settings.json`. Array order determines execution order. The design says "preference hooks run LAST in SessionStart, FIRST in PreToolUse." This ordering is required because:

- SessionStart must load existing context before preferences are injected on top of it.
- PreToolUse must validate before any other hook can act on the tool call.

The coexistence contract must define: what happens when a user adds a custom hook? What position does it go in? What happens when xgh adds a new skill that registers a PreToolUse hook — does the developer remember to put it after the preference validation hook? What happens when Claude Code itself changes hook execution semantics in a future version?

The answer the design gives is: "hook ordering validated by validate-project-prefs skill." This means: a skill that reads `.claude/settings.json` and checks that preference hooks are at the correct array indices. This is a linter for array positions. It will catch violations after they are committed. It will not prevent them. And it only runs when the user explicitly invokes validate-project-prefs — not on every hook registration.

The coexistence contract is actually a framework-level guarantee that Claude Code does not provide. The design is trying to implement it at the application layer with a linter. That is not a contract. It is a convention with a violation detector. Conventions get violated, especially by a solo developer working across multiple branches with multiple skills being added over time. Every new skill that registers a PreToolUse hook is a potential ordering violation. Phase 2 ships the preference hooks but leaves the contract as an honor system.

The real difficulty: there is no hook registration API in Claude Code. Hooks are static configuration. You cannot programmatically say "insert this hook at position 0 in PreToolUse." You can only write the array. So the "coexistence contract" is enforced by whoever edits `.claude/settings.json` being careful. That is not a contract.

---

## 3. What Breaks When Phase 1 Ships But Phase 2 Does Not (For Weeks/Months)

Phase 1 ships: lib/preferences.sh with 11 domain loaders, config-reader.sh becomes a wrapper, 4 dead preference blocks are wired, new domain skeletons are added to project.yaml, validate-project-prefs is updated.

Phase 2 does not ship: no SessionStart injection, no PostCompact re-injection, no hook coexistence contract.

**What breaks:**

1. **The 11 domain loaders exist but nothing calls them.** Skills still use the old config-reader.sh directly (now a wrapper that calls lib/preferences.sh underneath). The cascade resolution is now happening but the resolved values are not injected into the model's context. The model does not know that merge_method is squash unless a skill explicitly loads it. Phase 1 delivers plumbing that delivers no ambient awareness.

2. **The 4 "dead preference blocks" that are now wired have nowhere to go.** They load correctly in lib/preferences.sh but the hooks that would consume them (SessionStart for injection, PreToolUse for validation) do not exist. Wiring dead blocks without the consumers means the new domain skeletons in project.yaml are live configuration fields with no enforcement. A user adds `pr.protected_branches: [main, develop]` to project.yaml. Nothing enforces it. The field silently does nothing. The user assumes it is being enforced. This is worse than the field not existing.

3. **validate-project-prefs now validates schema that no running hook enforces.** The validation skill confirms project.yaml is well-formed. But the hooks that would act on it are not deployed. The skill gives the user a green checkmark on a configuration that has no runtime effect. Trust is established in a system that is not yet active.

4. **The config-reader.sh → wrapper migration creates a regression window.** Every existing skill that sources lib/config-reader.sh now goes through the wrapper. If the wrapper has any behavioral difference from the original (different defaults, different error handling, different return codes on missing keys), existing skills break. The migration is not transparent. Every skill is now dependent on the wrapper being a perfect behavioral shim. This is a non-trivial compatibility surface that the design treats as "migrate config-reader.sh to wrapper" in one bullet point.

5. **The new domain skeletons in project.yaml are inert fields that users may configure.** When Phase 2 eventually ships and starts injecting them, users who configured them during the Phase 1 gap will suddenly see new behavior appear. Configuration that was silently ignored for months becomes active. This is a breaking change in behavior that looks like a bug.

**Net result:** Phase 1 alone makes the system strictly worse. It adds schema, adds loaders, updates validation — but the user-visible behavior does not change, the new fields are inert traps, and the wrapper migration introduces a regression surface. The correct ship order would be Phase 1 + Phase 2 as a single release, or Phase 1 limited to only the non-breaking parts (loaders, wrapper) with domain skeletons and new fields held back until Phase 2 is ready.

---

## 4. Is There a Simpler Phasing That Delivers More Value Sooner?

Yes. The current phasing is organized around implementation layers (library first, then hooks, then more hooks, then capture, then routing). Users care about outcomes, not layers. Here is a value-first phasing:

**Revised Phase 1 — The One Hook That Matters:**
Ship SessionStart injection only. No lib/preferences.sh refactor, no wrapper migration, no domain skeletons. Just: SessionStart reads project.yaml preferences block, formats it as ~50-token index, injects via additionalContext. Every session now starts with ambient preference awareness. Users immediately feel the benefit. Cost: one hook file, ~30 lines of shell.

**Revised Phase 2 — The Validator People Will Actually Use:**
Ship /xgh-config show (read-only). Show what preferences are currently active, what they resolve to for the current branch, and what domain loaded them. This is the diagnostic tool that makes the system legible. Ship this before any validation or enforcement, because enforcement without observability produces confusion. Cost: one skill, shell + yq.

**Revised Phase 3 — PreToolUse for the One Case That Matters:**
The merge_method guard on `gh pr merge`. Not all 11 domains, not drift detection, not failure diagnosis. Just: if the tool is `gh pr merge --merge` and project.yaml says `merge_method: squash` for the target branch, block with a clear message. One domain, one tool, one check. Cost: one hook, 20 lines.

**Revised Phase 4 — Everything Else:**
All remaining hooks (PostCompact, PostToolUse, UserPromptSubmit, Stop), all remaining domains, /xgh-save-preferences, the full lib/preferences.sh refactor, the wrapper migration. This is the big phase, but by this point the system has already delivered real value in Phases 1-3 and the infrastructure is motivated by observed usage patterns.

**Why this is strictly better:** Revised Phase 1 ships in one afternoon and immediately benefits every session. Current Phase 1 ships in one sprint and immediately changes nothing visible.

---

## 5. Total Implementation Cost

The design lists five phases. Estimating realistically for a solo developer with existing xgh codebase context:

**Phase 1 — Foundation:**
11 domain loaders is not 11 lines each. Each loader requires: reading the relevant section from project.yaml (yq call), implementing the cascade resolution for that domain (CLI flag detection, branch matching, default fallback, probe fallback), error handling for missing sections, and tests that the cascade resolves correctly for each priority level. Realistic estimate: 4-6 hours per domain for initial implementation and manual testing. 11 domains = 44-66 hours. Plus wrapper migration regression testing: 8-12 hours. Plus validate-project-prefs update: 4 hours. **Total Phase 1: 6-10 days.**

**Phase 2 — Inject/Re-inject:**
SessionStart hook modification: 2-3 hours. PostCompact hook: 3-4 hours. Hook coexistence contract definition + validate-project-prefs update to check ordering: 4-6 hours. **Total Phase 2: 1-2 days.**

**Phase 3 — Validate/Observe:**
PreToolUse validation (per-domain guards, fast-exit parsing, stderr logging): 4-6 hours. PostToolUse drift detection (compare resolved vs. actual, emit delta): 4-6 hours. PostToolUseFailure diagnosis (correlate failure to preference state): 6-8 hours (this is the hardest because failure correlation requires knowing what the preference should have prevented). PermissionRequest policy hook: 4-6 hours. **Total Phase 3: 3-4 days.**

**Phase 4 — Capture/Converge:**
UserPromptSubmit silent detection (pattern matching, staging write, no interruption): 4-6 hours. Staging area implementation (session-scoped files, orphan cleanup, cross-session discovery): 8-12 hours (the orphan problem is non-trivial). Stop hook diff-aware reminder: 4-6 hours. /xgh-save-preferences skill (read staging, merge into project.yaml, conflict detection): 8-12 hours. **Total Phase 4: 4-6 days.**

**Phase 5 — Route/Extend:**
Notification routing (read preferences, apply routing rules per notification type): 4-6 hours. /xgh-config refresh: 2-3 hours. /xgh-config show: 3-4 hours. Cross-domain dependency validation: 6-10 hours (discovering what the dependencies actually are is the hard part). **Total Phase 5: 2-3 days.**

**Grand total: 16-25 days of focused implementation work.** For a solo developer who also ships PRs, reviews Copilot output, and maintains the existing codebase, this is 6-10 weeks of calendar time. The design does not include this estimate, which means the person who approved the phasing has not internalized the cost. The most likely outcome is that Phase 1 ships, Phase 2 ships partially (SessionStart but not PostCompact or the coexistence contract), and Phases 3-5 become perpetual backlog items that are always "next sprint."

---

## Summary Verdict

**Phase 4 will never ship as specified.** The staging area, orphan cleanup, and cross-session persistence are three separate unsolved problems bundled into one phase.

**The hook coexistence contract is secretly impossible.** It is a framework guarantee implemented as a linter convention. It will be violated.

**Phase 1 alone makes the system worse, not better.** Inert configuration fields, regression surface from wrapper migration, and green validation on a non-enforcing system erode user trust before Phase 2 arrives.

**Simpler phasing:** SessionStart injection (one afternoon) → /xgh-config show (one day) → PreToolUse merge_method guard (one day). Three days of work, full value delivery, no dead fields, no orphan staging areas.

**Total cost: 16-25 developer days.** At solo developer pace, this is 6-10 weeks. Budget for it or scope it down.
