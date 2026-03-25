---
title: Against-Agent Evaluation 1 — Declarative Preferences with Explicit Convergence
role: AGAINST (persistent skeptic)
date: 2026-03-25
---

# Against-Agent Evaluation 1

## Framing

The design being evaluated claims to solve "config drift" by making project.yaml the single source of truth for AI behavior, with a hook lifecycle that reads but never auto-writes, and an explicit convergence step (/xgh-save-preferences). This is architecturally cleaner than GLM's proposed reconciler. But cleaner architecture does not equal correct behavior. Here are the failure modes the designers are not seeing.

---

## 1. Top 3 Flaws — Concrete Failure Scenarios

### Flaw 1: UserPromptSubmit Intent Detection Will Misfire in Ways That Erode Trust Permanently

The design says UserPromptSubmit detects preference-setting language and injects additionalContext asking Claude to confirm. The hook analysis lists these signal patterns:

```
(always|default to|set|use|change) .* (squash|merge|rebase)
```

The problem is not false positives being caught before write — it is that every false positive produces an interruption. The user says "I always use squash here, it keeps history clean" while explaining something to a colleague in a Copilot chat. The hook fires. Claude pivots to asking "Should I save `merge_method: squash` to project.yaml?" The user is confused. This happens three times in a week. The user disables the hook. The entire preference capture pipeline is now dead, and they never re-enable it because there is no visibility into what the hook is doing or why it fired.

The designers addressed false positives abstractly ("use conservative anchored patterns") but did not address the trust erosion from even occasional interruptions in a conversational context. The hook has no suppression mechanism, no cooldown, no way to say "I was just explaining, not declaring." The design treats conversational text as a command interface, which it is not.

**The fix the design is missing:** A pending preference should not surface as an in-conversation interruption. It should be invisible until the user explicitly invokes /xgh-save-preferences. The detection should be silent and the Stop hook reminder should be the only signal. This is not what the current design does — the "inject additionalContext asking Claude to confirm" path creates an interactive loop mid-task.

### Flaw 2: Branch Override Resolution Is Undefined for the Most Common Real Workflow

The design specifies that branch overrides live under `branches.<ref>` in project.yaml and the cascade resolves by matching the current branch. The lib/preferences.sh cascade for PR is:

```
CLI > branch override > project default > auto-detect probe
```

"Current branch" is defined implicitly as the checked-out branch at hook execution time. This breaks immediately in the most common real workflow: a PR from `feature/foo` targeting `main`, where the user is on `feature/foo` and the relevant override is on `main`.

Example: main requires squash (protected branch, merge queue enforces squash). The user sets:
```yaml
pr:
  branches:
    main:
      merge_method: squash
```

They are on `feature/foo`. The PreToolUse hook resolves the branch as `feature/foo`. There is no override for `feature/foo`. The cascade falls to the project default. If the default is `merge`, the hook approves a merge operation that the remote will reject. The hook then does nothing useful at the only moment it could have been useful.

The design explicitly notes "PostCompact re-resolves for CURRENT branch" — this is the same wrong resolution. The preference should be resolved against the PR's BASE branch (the merge target), not the checked-out branch. The design has no mechanism to determine the base branch at hook time without a `gh pr view` call, which adds latency and a network dependency to every PreToolUse invocation on a Bash tool.

**This is not a minor edge case.** This is the primary use case. Branch-specific merge methods exist precisely to protect target branches.

### Flaw 3: The Staging Area Pattern Creates a Data Integrity Gap Between Sessions

The pending-preferences-<session-id>.yaml files are gitignored and session-scoped. The Stop hook fires a one-shot reminder. The design considers this solved.

What actually happens:

1. User has 4 pending preferences accumulated over a 2-hour session.
2. The Stop hook fires and adds a reminder to Claude's context. Claude says "You have 4 pending preferences. Run /xgh-save-preferences."
3. The user's machine crashes, or they close the terminal, or they /clear the session, or the Claude Code process is killed.
4. The session ID is gone. The pending-preferences file is still on disk under the old session ID. The next session starts fresh with a new session ID. The old pending file is orphaned.

The design has no cleanup, no discovery of orphaned pending files, and no mechanism to carry pending preferences across session boundaries. After one interrupted session, the user has learned that intent expressed in conversation evaporates. They stop trusting the system. The trust erosion from Flaw 1 is compounded here.

The designers will say "the user can just re-state the preference." This is exactly the behavior the system is supposed to eliminate.

---

## 2. The Assumption Most Likely to Be Wrong

**The assumption: Claude's conversational output is a reliable signal for preference capture.**

The entire explicit convergence model depends on Claude correctly identifying preference-setting intent in conversation, reasoning about whether to write to the staging area, and then surfacing it accurately in the Stop reminder. Claude is not a deterministic system. Its output varies by model version, context window state, and prompt phrasing.

Concretely: the UserPromptSubmit hook injects additionalContext asking Claude to confirm. Whether Claude writes to the staging area depends on Claude's interpretation of the confirmation request, which depends on what else is in context, what the model version is, and whether the preference statement is buried in a long prompt. The designers are treating an LLM as a reliable conditional execution engine. It is not.

This is the foundational assumption that makes the entire pipeline fragile. If Claude misses 30% of preference-setting signals, the system has 30% silent data loss. If it over-fires 20% of the time, users disable it. There is no SLA, no test suite, and no observability that would catch either failure mode in production.

---

## 3. What Happens at Scale — 50+ Fields Across 11 Domains

**The injection token cost becomes a negotiation, not a feature.**

The design says SessionStart injects preferences as additionalContext at ~200 tokens. With 11 domains and 50+ fields, that estimate is optimistic. A fully-populated project.yaml with branch overrides per domain (4+ branches) is closer to 800-1200 tokens per injection. PostCompact re-injects this every time compaction occurs.

In a long working session: compaction fires 3 times. Each re-injection adds 1000 tokens. That is 3000 tokens of configuration scaffolding in a session that is already being compacted because the context window is under pressure. The design is adding context window load at the moment the system is trying to reduce it.

**The domain loader proliferation creates an untestable surface.**

11 domain loaders, each with its own fixed cascade, means 11 independent implementations of cascade resolution. Each one is slightly different (the design acknowledges different cascades: "CLI > branch > default > local probe" for PR vs "CLI > default" for most domains). When a preference is not resolving correctly, the user has to know which domain loader to inspect. There is no unified diagnostic. The design has no /xgh-debug-preferences command.

**Schema drift becomes a maintenance tax.**

When project.yaml gains a new field in domain 7, lib/preferences.sh needs a new getter in the domain 7 loader, all hook implementations that reference domain 7 need updating, and the SessionStart injection template needs to include the new field. This is 3-4 coordinated changes per new field. At 50 fields, one new field per week, that is a non-trivial ongoing cost for a solo developer.

---

## 4. The Integration Nightmare

**The hook ordering guarantee is load-bearing and fragile.**

The design specifies: preference hooks run LAST in SessionStart, FIRST in PreToolUse. This ordering matters because existing hooks already run in SessionStart (trigger bus initialization, staleness checks) and PreToolUse (write guards). The preference hooks are bolted onto these existing chains.

The problem: Claude Code's hook ordering is defined in `.claude/settings.json` as an array. If any other hook is added in the future (new xgh skill, user customization, Copilot integration), it goes into the array at some position. There is no semantic ordering — only array index. The guarantee that preference hooks run FIRST in PreToolUse is maintained by array position discipline, not by the framework. One new hook added by a non-preference contributor breaks the ordering silently.

The designers said "hook ordering defined" as if this closes the issue. It closes nothing. It creates a fragile convention that will be violated.

**The PreToolUse hook fires on every Bash tool call.**

The design validates tool args against preferences in PreToolUse. For a Bash tool, this means: parse stdin JSON, extract command, run yq against project.yaml, check merge_method, emit decision. This runs on every `git status`, every `ls`, every `echo`. The fast-exit guard is essential but adds parsing overhead to every single tool call. The PostToolUse analysis explicitly warns: "Python3 YAML parsing adds 80-150ms per call. Over a long session with hundreds of tool uses, this compounds." The designers acknowledged this pitfall for PostToolUse but did not resolve it for PreToolUse where validation actually runs.

**The permission-request hook creates a policy gap during initial setup.**

The PermissionRequest hook reads project.yaml to apply auto-approve/deny policies. On a fresh install, project.yaml has no permissions section. The hook has no defaults — it falls through and allows everything. This means the "config-driven security policy" provides no security until the user has configured it. A new xgh user installing the hooks believes they have guardrails from day one. They do not.

---

## 5. What GLM-4.7 Got Right That Was Dismissed

GLM's design-challenge.md made five substantive criticisms. Three were addressed. Two were waved away.

**Branch override resolution ambiguity — waved away.**

GLM explicitly described: "Alice creates a PR from `feature/user-auth` to `release/1.0`. Which merge method is used?" The design response was "fixed cascade per domain." This does not answer the question. The cascade resolves against one branch. Which branch? The current analysis says the current checked-out branch. GLM was right that this is undefined, and the design closed it with "fixed cascade" language that sounds resolved but is not. See Flaw 2 above.

**Performance overhead for network probes — waved away as already solved.**

GLM noted network probes are the real bottleneck (not YAML parsing). The design response: "probes only run at init time, already cached in project.yaml via probe-and-cache." This is correct for existing probes. But the design adds NEW probes: staleness checks against git remote in SessionStart, Copilot policy checks in PermissionRequest. These are new network round-trips added by the preferences design that did not exist before. GLM's point applies directly to the new hooks, not just the existing implementation. The dismissal addressed the existing system, not the proposed additions.

**Cache corruption causing session failure — partially waved away.**

GLM's scenario: corrupted /tmp/xgh-session.yaml bricks the session. The design eliminated the session cache. This correctly addresses the scenario. But the staging area (pending-preferences-<session-id>.yaml) is now the new file that can be corrupted. The design says it is gitignored and session-scoped but does not specify validation, recovery, or what happens when the file is malformed. The same class of bug persists in a different artifact. The design eliminated the cache but created a staging area with identical fragility characteristics and less attention to failure modes.

---

## Summary Verdict

The design is significantly better than GLM's proposed reconciler. Eliminating the session cache was the right call. Explicit convergence via /xgh-save-preferences is the right model.

But three structural problems remain unresolved:

1. The branch resolution is wrong for the primary use case (PR targeting a protected branch from a feature branch).
2. The conversational preference capture creates trust-eroding interruptions and loses data across session boundaries.
3. The hook ordering guarantee is a convention maintained by array index discipline, which will be violated.

These are not implementation details. They are architectural gaps that will produce visible failures in normal daily use. Fix the branch resolution semantics (resolve against PR base, not checked-out branch). Make the preference capture fully silent until /xgh-save-preferences is explicitly invoked. Add session-orphan discovery to the staging area cleanup logic.
