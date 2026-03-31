---
role: Adversary
date: 2026-03-27
scope: Full branch feat/phase-2-validate-observe vs develop (26 commits)
---

# ADVERSARY: The Strongest Case AGAINST This Branch

## 1. Real Failure Modes (Not Theoretical -- These Actually Break)

### CRITICAL: 40+ dangling references to deleted `_shared/references/` files

The skill cleanup deleted all files in `skills/_shared/references/` but **did not update the surviving skills that reference them**. A grep reveals at least 40 dangling references across files that are still active:

**Commands referencing deleted `execution-mode-preamble.md`:**
- `commands/codex.md:35`
- `commands/gemini.md:17`
- `commands/glm.md:17`
- `commands/opencode.md:17`
- `commands/track.md:12`

**Skills referencing deleted `dispatch-template.md`:**
- `skills/codex/codex.md` (6 references: lines 10, 78, 117, 125, 131, 260)
- `skills/gemini/gemini.md` (6 references)
- `skills/glm/glm.md` (6 references)
- `skills/opencode/opencode.md` (6 references)

**Skills referencing deleted `memory-backend.md`:**
- `skills/codex/codex.md:129`
- `skills/gemini/gemini.md:141`
- `skills/glm/glm.md:128`
- `skills/opencode/opencode.md`
- `skills/doctor/doctor.md:42`
- `skills/index/index.md:81`

**Skills referencing deleted `project-resolution.md`:**
- `skills/architecture/architecture.md:10`
- `skills/index/index.md:10`

**Skills referencing deleted `mcp-auto-detection.md`:**
- `skills/briefing/briefing.md:28`
- `skills/profile/profile.md:26`

**Skills referencing deleted `project-preferences.md` and `providers/`:**
- `skills/watch-prs/watch-prs.md` (3 references)
- `skills/validate-project-prefs/validate-project-prefs.md:35`

**Impact:** When Claude reads these skills and follows the "Follow the shared protocol in..." instruction, it will try to read a file that does not exist. This will cause a tool error or hallucinated behavior on every invocation of codex, gemini, glm, opencode, track, architecture, briefing, index, doctor, profile, and watch-prs. That's the majority of the skill surface area.

**This is not a cosmetic issue.** Skills that say "Follow the shared protocol in X.md" are non-functional when X.md doesn't exist.

### Iron Law violation: new skills have zero tests and zero trigger prompts

The project's AGENTS.md says: "If you call it, test it -- every skill invoked during a session must have a prompt in tests/skill-triggering/prompts/." The branch adds two new skills (`for-against`, `plugin-integrity`) with:
- No test files in `tests/`
- No trigger prompts in `tests/skill-triggering/prompts/`
- No assertions in any test suite

This violates Iron Law #5 explicitly.

### 3 orphaned commands with deleted backing skills

`commands/ask.md`, `commands/curate.md`, and `commands/status.md` still exist and reference skills that were deleted (`skills/ask/ask.md`, `skills/curate/curate.md`). When a user runs `/xgh-ask`, Claude will try to read a skill that doesn't exist.

## 2. Fresh Install / Edge Case Gaps

- **`commands/codex.md` has a "How to dispatch" section AND a "Preamble -- Execution mode" section that references deleted files.** A fresh user running `/xgh-codex` gets instructions pointing to a non-existent file. Same for `/xgh-opencode`, `/xgh-gemini`, `/xgh-glm`, `/xgh-track`.
- **`commands/codex.md` moved the Preamble INTO the command** (lines 26-35) instead of removing it. This is inconsistent with the thin-wrapper pattern that every other command follows. Codex command now has dispatch logic AND a preamble AND a "Read and follow..." pointer.

## 3. What a Code Reviewer Would Catch

- **The test suite passes but is not testing for the actual bugs.** No test checks that skills don't reference non-existent files. The test update was purely subtractive (removing assertions for deleted files) without adding assertions for the new state (e.g., "no skill references a path under `_shared/references/`").
- **The shellcheck hook (`post-tool-use-shellcheck.sh`) is registered in `.claude/settings.json` as a PostToolUse hook with matcher `Write|Edit|MultiEdit`, but it's listed AFTER `post-tool-use-preferences.sh`.** If preferences.sh errors (which it shouldn't, but fail-open design means it silently passes), shellcheck still runs. But if shellcheck errors, it could mask preferences output. Hook ordering is not tested.
- **`plugin.json` now declares `"commands": "./commands/"` etc., but the plugin cache won't reflect this until the cache is rebuilt.** Users who have xgh installed won't see the change until they `rm -rf` cache and `/reload-plugins`.

## 4. Better Alternatives (Concrete)

1. **Before deleting `_shared/references/`, grep all skills/commands for references and update them.** This is a 30-minute task: find every `_shared/references/` path, inline the essential content or remove the reference. Ship the deletion and reference cleanup as one atomic commit.

2. **Delete the 3 orphaned commands** (`ask.md`, `curate.md`, `status.md`) in the same cleanup commit rather than leaving broken commands in the palette.

3. **Add a `test-no-dangling-references.sh` test** that greps all `.md` files for paths and verifies the referenced files exist. This prevents future deletions from creating the same problem.

4. **Add trigger prompts** for `for-against` and `plugin-integrity` to satisfy Iron Law #5 before committing.

## Summary

The branch has a critical bug: it deleted 12 shared reference files but left 40+ dangling references to them across the surviving skills and commands. Every dispatch skill (codex, gemini, glm, opencode), plus architecture, briefing, doctor, index, profile, track, and watch-prs will break when invoked because they instruct Claude to read files that no longer exist. The tests pass because no test checks for dangling references. Fix the references before merging.
