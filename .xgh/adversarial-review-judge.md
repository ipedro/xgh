---
role: Judge
date: 2026-03-27
scope: Full branch feat/phase-2-validate-observe vs develop (26 commits)
---

# JUDGE VERDICT

## Ruling: CONDITIONAL SHIP -- fix dangling references before merge

The Enthusiast is correct that the Phase 2 hooks are well-implemented, the skill cleanup is the right direction, and the -5,000 line reduction is valuable. The Adversary is correct that the cleanup is incomplete: deleting shared references without updating the 40+ files that reference them is a ship-blocking bug.

## Required Fixes (must complete before merge)

### Fix 1: Remove all dangling `_shared/references/` paths from surviving skills and commands

**Scope:** 5 commands + ~12 skills contain references to deleted files in `skills/_shared/references/`. Each reference instructs Claude to "Follow the shared protocol in X.md" -- when X.md doesn't exist, the skill breaks.

**Action:**
- For `execution-mode-preamble.md` references in commands (codex, gemini, glm, opencode, track): Remove the Preamble section entirely. Commands should be thin wrappers; the preamble was boilerplate.
- For `dispatch-template.md` references in dispatch skills (codex, gemini, glm, opencode): Inline the essential step references or remove the cross-references. The dispatch skills already contain their own step implementations.
- For `memory-backend.md` references: Replace with direct `[STORE]`/`[SEARCH]` intent labels (the memory abstraction pattern already exists in the skills).
- For `project-resolution.md`, `mcp-auto-detection.md`, `project-preferences.md`, and `providers/` references: Remove or inline the essential content.

### Fix 2: Delete orphaned commands

**Action:** Delete `commands/ask.md`, `commands/curate.md`, and `commands/status.md`. Their backing skills were deleted; leaving broken commands in the palette is worse than having no command.

### Fix 3: Add trigger prompts for new skills

**Action:** Create `tests/skill-triggering/prompts/for-against.txt` and `tests/skill-triggering/prompts/plugin-integrity.txt` to satisfy Iron Law #5.

### Fix 4: Add a dangling-references test

**Action:** Add a test that greps all `.md` files for `_shared/references/` paths and verifies no matches. This prevents regression.

## Recommended (not blocking)

- Normalize `commands/codex.md` to the thin-wrapper pattern (it currently has dispatch logic + preamble + pointer, unlike other commands).
- Update `tests/test-commands.sh` to remove assertions for deleted commands (ask, curate).

## Scoring

| Dimension | Enthusiast | Adversary | Verdict |
|-----------|-----------|-----------|---------|
| Phase 2 hooks quality | Strong | Not contested | Ship as-is |
| Skill cleanup direction | Strong | Not contested | Right approach |
| Dangling references | Dismissed as cosmetic | **Critical bug** | **Adversary wins** -- must fix |
| Orphaned commands | Noted as follow-up | Ship-blocking | Adversary wins -- fix now |
| Missing tests for new skills | Not addressed | Valid Iron Law violation | Adversary wins -- fix now |
| Shellcheck hook | Clean addition | Hook ordering concern | Minor -- not blocking |

**Net assessment:** The branch is 90% done. The remaining 10% (dangling references, orphaned commands, missing test prompts) is mechanical cleanup that should take ~1 hour. Do not merge until Fix 1-4 are complete.
