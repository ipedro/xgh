# FOR Agent — Evaluation 2: Phased Epic Breakdown

## Role
Persistent advocate for the "Declarative Preferences with Explicit Convergence" design.
Continuing from Evaluation 1. Evaluating the 5-phase epic breakdown as specified.

---

## 1. Is the Phasing Correct? Any Epic in the Wrong Phase?

The phasing is mostly correct. Four issues worth flagging:

### 1a. `validate-project-prefs` update belongs at the END of Phase 1, not alongside the skeletons
Phase 1 includes "update validate-project-prefs" as a deliverable. But validate-project-prefs is a consumer of the preferences API — it calls the domain loaders to check that what's in project.yaml resolves without error. You cannot write a meaningful validator until all 11 domain loaders exist and their return contracts are stable. If validate-project-prefs is updated in the same phase that introduces the loaders, it will either be incomplete (some loaders not yet wired) or it will require the entire Phase 1 to land atomically. The epic is correctly placed in Phase 1 only if it's understood to be the LAST task in the phase, not a parallel deliverable. This should be made explicit in the plan.

### 1b. Hook coexistence contract belongs in Phase 1, not Phase 2
"Hook coexistence contract" is listed as a Phase 2 deliverable. But coexistence rules (preference hooks run LAST in SessionStart, FIRST in PreToolUse) are architectural constraints that govern all existing hooks from the moment Phase 2 hooks are wired. If the contract is defined in Phase 2 alongside the hooks it governs, there is no document for Phase 2 implementers to reference during development. The contract should be defined as a Phase 1 artifact — a short CLAUDE.md section or a hook ordering table in project.yaml — so that Phase 2 (and Phase 3) hooks are implemented against a stable spec from the start.

### 1c. `/xgh-stage-preference` skill is missing entirely
Phase 4 includes the staging area and `/xgh-save-preferences`. But per Evaluation 1 (S1), the write path into the staging area must be a skill call — `/xgh-stage-preference domain field value` — that Claude calls explicitly, not the hook writing directly. This skill is not listed in any phase. It belongs in Phase 4 alongside the staging area, since it is the mechanism that makes silent detection actually write anything. Without it, the staging area is inert.

### 1d. PostToolUse drift detection needs a definition of "drift"
Phase 3 lists "PostToolUse drift detection" but does not define what drift means in this context. Drift from what baseline? The most defensible interpretation is: drift between the resolved preference value (from lib/preferences.sh) and what Claude actually used in the tool call output. But PostToolUse has access to tool results, not Claude's reasoning about why it made a choice. This epic is either (a) detecting whether project.yaml was directly modified by a Write/Edit call (the S2 guard from Evaluation 1 — cheap and well-defined) or (b) trying to infer preference adherence from tool output (expensive, unreliable). The epic needs to pick one. If it's (a), it belongs in Phase 3. If it's (b), it should be descoped or moved to Phase 5 as a future investigation.

---

## 2. Are the Dependencies Right? Anything That Should Be Parallel That Isn't?

The stated dependency graph is: Phase 1 → Phase 2 → Phase 3 (parallel with Phase 4). Phase 5 needs only Phase 1.

**This is correct with one amendment:**

Phase 3 and Phase 4 are listed as parallel after Phase 2. This is accurate — PreToolUse validation (Phase 3) and UserPromptSubmit capture (Phase 4) are both consumers of lib/preferences.sh (Phase 1) and do not depend on each other. However, they share one artifact: the staging area. If Phase 3's PostToolUse drift detection is defined as the S2 guard (detecting direct project.yaml edits), it also writes to the audit trail, which may or may not be the same file as the pending-preferences staging area. If they share a file path or session-id namespace, Phase 3 and Phase 4 have an implicit coupling that must be resolved before parallel implementation can proceed. Recommend: define the staging area schema (path pattern, YAML structure) as a Phase 1 artifact alongside the hook coexistence contract.

**Phase 5 parallelism is understated.** `/xgh-config show` and `/xgh-config refresh` depend only on lib/preferences.sh (Phase 1). Cross-domain dependency validation depends on all domains being stable (Phase 1). Notification routing depends on knowing which preferences trigger notifications — which is a question of domain definition (Phase 1) not hook implementation. Phase 5 could realistically be started as a parallel track after Phase 1 completes, not blocked on Phase 2–4. This means Phase 5 is not a "final phase" — it is an ongoing parallel track. Reframing Phase 5 as "always available after Phase 1" reduces the timeline by weeks if the team (or parallel agents) can work on it alongside Phases 2–4.

---

## 3. What's the Riskiest Epic?

**PostToolUse drift detection (Phase 3) is the riskiest epic.**

Reasons:

1. **Undefined scope.** As noted above, "drift" is ambiguous. Two entirely different implementations hide behind the same label. The implementation team will make different assumptions.

2. **High-frequency path.** PostToolUse fires after every tool call. A buggy drift detector that throws an exception or produces spurious output will degrade every session, not just sessions that touch preferences. The blast radius is maximal.

3. **False positive risk.** If drift detection compares expected vs. actual behavior, false positives will erode user trust in the system. A preference that says `merge_method: squash` but a Bash tool call that runs `git merge` for an unrelated reason will look like drift. The hook cannot distinguish context without Claude's reasoning, which it does not have access to.

4. **Interaction with PreToolUse validation.** If PreToolUse already validates the preference before the tool call and blocks non-conforming calls, what does PostToolUse drift detection add? The phases don't define the relationship between these two hooks. There is a risk of redundant checking or conflicting signals.

The riskiest epic needs a narrow scope definition before Phase 3 starts: drift detection = detecting direct writes to project.yaml (S2 guard from Evaluation 1). Everything else is descoped.

---

## 4. What's Missing from the Epics?

### M1. `/xgh-stage-preference` skill (Phase 4 gap)
Already noted above. The confirmation write path is unspecified. Without it, Phase 4 captures signals but cannot act on them.

### M2. gitignore entry for staging area files
`.xgh/pending-preferences-<session-id>.yaml` must be gitignored. This is a one-line change but it must land in Phase 1 (when the staging area schema is defined) or Phase 4 will produce untracked files that dirty the working tree — exactly the failure mode the design exists to prevent.

### M3. Orphan cleanup scope definition (Phase 4)
Phase 4 includes "orphan cleanup" for staging area files from terminated sessions. The definition of "orphan" is not specified: is it based on session-id TTL? On session-id presence in an active process list? On file age? Without a definition, implementers will make incompatible choices, and the cleanup logic may delete files from parallel agent sessions (the parallel-agent commit loss bug pattern documented in this codebase's memory). Orphan cleanup needs a definition: files older than N hours with no matching active session-id in a lockfile.

### M4. No rollback path for `/xgh-save-preferences`
Phase 4 ships `/xgh-save-preferences` but does not specify what happens if the write fails (file locked, YAML parse error in the pending file, disk full). A failed save must not silently drop pending preferences. The skill needs a `--dry-run` flag that shows what would be written, and a failure mode that leaves the staging file intact so the user can retry.

### M5. Hook ordering enforcement is specified but not tested
Phase 1 adds hook ordering to validate-project-prefs. But the validation is a linting check — it catches wrong ordering in config but cannot enforce runtime ordering if hooks are registered outside the standard config (e.g., a manually edited .claude/settings.json). The epic should specify what validate-project-prefs actually checks: the JSON array order of hook entries, not runtime behavior. This is achievable and worth stating explicitly.

### M6. Branch resolution contract for non-git contexts
The design says "branch resolution uses target_branch parameter (caller provides), not git branch --show-current." This is correct. But what does the cascade fall back to when the caller does not provide target_branch (e.g., a skill run in a non-git directory, a detached HEAD, a bare repo)? The fallback to project default (skipping the branch override tier) must be defined in Phase 1 as part of the loader contract, not left to each loader to handle independently.

---

## Summary Verdict

The phasing is sound. The dependency graph is mostly right with one amendment (Phase 5 is parallelizable with Phases 2–4, not blocked on them). Two adjustments to Phase 1 would prevent downstream pain: move the hook coexistence contract into Phase 1, and define the staging area schema (including gitignore entry) as a Phase 1 artifact. The riskiest epic is PostToolUse drift detection — it needs a scope definition before Phase 3 starts. The most significant omission is `/xgh-stage-preference`, without which Phase 4's capture pipeline has no write path.

---

## Status
Evaluation 2 complete. Phase analysis done. Awaiting further design sections.
