---
role: Enthusiast
date: 2026-03-27
scope: Full branch feat/phase-2-validate-observe vs develop (26 commits)
---

# ENTHUSIAST: The Strongest Case FOR This Branch

## 1. Core Strengths

**Phase 2 hooks are the real infrastructure this project was missing.** Before this branch, xgh had preferences in `project.yaml` but no enforcement. Now there are three hooks that form a closed feedback loop:
- **PreToolUse** (5 severity-aware checks) prevents bad commands before they run — merge method, branch protection, commit format, branch naming, force push. Each check reads severity from `project.yaml`, defaulting to safe values (block for safety, warn for convention).
- **PostToolUse** detects preference drift after writes — if `project.yaml` changes unexpectedly, the operator knows which fields changed and why.
- **PostToolUseFailure** diagnoses `gh` CLI failures with targeted fix suggestions — merge method mismatch, stale reviewer, wrong repo, auth failure, rate limiting. Instead of a raw stderr dump, the user gets "Check preferences.pr.merge_method (currently: squash)."

This is a shift from "declare preferences" to "enforce preferences." That's the whole thesis of xgh: declarative AI ops.

**The skill cleanup is overdue housekeeping that improves every future session.** The numbers tell the story: -5,109 lines, +507 lines. The branch:
- Removes 28 skills/references that were either unused, redundant, or unreachable (team skills nobody invoked, shared references that duplicated what `project.yaml` already provides, skills like `implement` and `investigate` whose logic was never actually callable through the plugin).
- Trims surviving skills by removing boilerplate (Preamble/execution-mode sections that referenced a now-deleted shared reference).
- Makes commands thin pointers (`Read and follow the implementation spec at skills/X/X.md`), eliminating usage duplication between commands and skills. Before: usage was in both. After: usage is in skills only, commands just redirect.
- Adds explicit `commands`/`skills`/`agents` paths to `plugin.json`, which was previously relying on implicit discovery.

This reduces token cost for every skill invocation (less boilerplate to read) and makes the skill-command relationship unambiguous.

**`lib/severity.sh` is a clean, minimal abstraction.** 33 lines. Bash 3.2 compatible (case statement, no associative arrays). Two functions: `_severity_defaults` (hardcoded safe defaults) and `_severity_resolve` (read from config, fall back to defaults). It's exactly the right size — no provider abstraction, no polymorphism, just "read the config or use safe defaults."

## 2. Why Alternatives Are Worse

- **Not enforcing preferences at all** means xgh is just a fancy YAML editor. Without hooks, `project.yaml` is aspirational, not operational.
- **Keeping the 28 deleted skills** means every session loads dead code into context. Skills like `collab`, `agent-collaboration`, `cross-team-pollinator`, and `subagent-pair-programming` were spec-driven designs that never shipped implementation. They consumed tokens without providing value.
- **Keeping usage in both commands and skills** means every update requires editing two files. The thin-wrapper pattern is the standard Claude Code plugin convention — commands delegate, skills implement.
- **Building a provider abstraction for the hooks** (the Option C debate) would add 3-5x code for 0 non-GitHub users. The branch correctly chose GitHub-only, matching the actual user base.

## 3. Failure Modes Considered and Why They Don't Apply

- **"Deleted skills might be needed later"**: All deleted skills are in git history. If any are needed, `git checkout develop -- skills/X/X.md` restores them in seconds. The cost of carrying dead skills (token waste, stale tests, maintenance burden) exceeds the cost of restoring one.
- **"Test changes mask real failures"**: The test changes are precise — they remove assertions for deleted files and update assertions for the new command pattern. No existing test logic was weakened; only expectations for removed code were removed.
- **"Shellcheck hook adds latency"**: It only fires on Write/Edit/MultiEdit of `.sh` files, exits silently if shellcheck isn't installed, and adds zero overhead for non-shell edits.
- **"Orphaned commands (ask, curate, status) are broken"**: They still exist on disk and their content is valid markdown. They just don't have backing skills anymore. A follow-up cleanup is appropriate, not a blocker.

## Summary

This branch delivers the enforcement layer that makes xgh's preference system real (Phase 2 hooks), cleans up 5,000+ lines of dead weight, and establishes the thin-wrapper pattern for all commands. The new skills (for-against, plugin-integrity) and shellcheck hook are well-scoped additions. The 148/148 test suite passes cleanly. Ship it.
