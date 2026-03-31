---
title: "FOR Option (C): Phase 2 Done Means Shipped + Dogfooded"
analyst: FOR agent
date: 2026-03-25
context: Phase 2 definition-of-done debate (hooks + tests vs. + validation skill vs. + real workflow)
---

# FOR Option (C) — Hooks + Tests + Validation Skill + Real Workflow Dogfooding

**Thesis**: Phase 2 is not "done" when code ships. It's done when the 3 hooks (PreToolUse, PostToolUse, PostToolUseFailure) *work in a real PR workflow and the validation skill covers the preferences they enforce*. Dogfooding is not nice-to-have polish—it's the only way to catch integration bugs that unit tests miss.

---

## 1. **Unit Tests ≠ Integration Tests: The Async/Multi-Hook Integration Gap**

The Phase 2 hooks are *sequential and stateful*:

- **PreToolUse** (project.yaml → inject flags) fires BEFORE `gh pr merge`
- **PostToolUse** (drift detection) fires AFTER merge succeeds
- **PostToolUseFailure** (error diagnosis) fires ONLY if merge fails
- **validate-project-prefs** (expanded) must audit that all three hooks agree on which preferences apply

In isolation, each hook can be unit tested: "given this YAML, inject these flags" ✓. But the *interactions* between hooks are invisible to unit tests:

- What if `project.yaml` is modified during PostToolUse *while* PreToolUse is still executing in another session? (collision)
- What if validate-project-prefs runs after PostToolUse but uses an outdated config cache? (staleness)
- What if PostToolUseFailure's error message references a preference key that validate-project-prefs doesn't recognize? (schema drift)
- What if the three hooks have conflicting interpretations of "merge_method: auto"? (semantic gap)

**These bugs exist in gaps between hooks**. They don't appear in unit tests because unit tests run each hook in isolation. Only a real PR workflow—where all three hooks fire in sequence, with real user interruptions and timing variations—will surface these gaps.

---

## 2. **Validation Skill Expansion = Preflight Check That Changes Phase 2's Risk Profile**

Option (C) proposes expanding validate-project-prefs to cover PreToolUse/PostToolUse/PostToolUseFailure logic, not just the config schema.

Current validate-project-prefs only validates YAML syntax and required fields. It doesn't validate *semantic correctness*:

- Is `merge_method` a value that GitHub actually supports? (should be: `squash|merge|rebase`)
- If `merge_method: auto`, does that require `merge_strategy` to be set? (conditional validation)
- Does `reviewer` refer to a GitHub user that exists in this repo? (external validation)
- Does `auto_merge_method` contradict `merge_method`? (intra-field consistency)

**Why it matters**: validate-project-prefs becomes the *preflight checker* for whether the hooks will succeed. If you run `/validate-project-prefs` and it passes, you have high confidence that PreToolUse won't inject invalid flags, PostToolUse won't crash on drift detection, and PostToolUseFailure will have the right context to diagnose errors.

Without expanding validate-project-prefs, operators have no way to catch configuration errors before they fail in production (i.e., during a real PR merge). With it, they can `/validate` early, fix issues, and approach Phase 2 with confidence.

This is the difference between:
- **Option (A/B)**: "I hope the hooks work when I actually use them."
- **Option (C)**: "I validated the config, I ran the hooks on a real PR, I know they work."

---

## 3. **Dogfooding Catches Integration Bugs and UX Debt You Can't Imagine**

You've written the hooks. You've written tests. You're confident. Then you run a real PR merge and discover:

- PostToolUse's drift detection emits JSON that validate-project-prefs can't parse (version mismatch).
- The PreToolUse flag injection works, but the hooks don't have permission to read `project.yaml` in this GitHub Actions runner context (file access).
- PostToolUseFailure's error message references `pr.merge_method` but the actual setting in `project.yaml` is under `github.pr.merge_method` (namespace drift).
- The three hooks agree on the merge method, but GitHub's API rejects it because the branch protection rule overrides it (policy collision).
- validate-project-prefs passes, but PreToolUse still fails because `jq` is not installed in the hook environment (environment assumption).

**None of these bugs are caught by unit tests**. They only surface in a real workflow where:
- Real GitHub Actions runners with their own environments execute the hooks
- Real rate limits and API throttling affect tool execution
- Real permission models determine what files the hooks can read
- Real branch policies and PR settings interact with hook logic

Shipping without dogfooding means the first real user to use Phase 2 will hit these bugs. On your own codebase (xgh), you can fix them quickly and own the UX debt. On a user's codebase (closed-source, with different GitHub org policies), they will face a broken feature with no support path.

---

## 4. **"Dogfooding" Means One Real PR: You Use Phase 2 to Merge a Real xgh PR**

Option (C) is not asking for a month of testing. It's asking for:

1. **Pick a real xgh PR** (e.g., next /release PR, or an existing in-flight PR on develop)
2. **Set up Phase 2 hooks** in xgh's `.xgh/hooks/` directory with real implementations
3. **Configure project.yaml** with merge preferences (e.g., `merge_method: squash`)
4. **Run `/validate-project-prefs`** and fix errors
5. **Merge that PR using the hooks** — observe that PreToolUse injects flags, PostToolUse detects no drift, PostToolUseFailure is not needed
6. **Log the session** — include hook execution times, flag values, validation results
7. **Ship with confidence** that the hooks work in your own workflow

That's 2–4 hours of work. It's the difference between shipping a feature you've tested and shipping a feature you've *used*.

---

## Summary: 4 Bullets

- **Integration bugs hide in gaps**: Unit tests validate each hook in isolation. Real workflows expose multi-hook interactions, timing issues, permission models, and API policy collisions that no unit test will find.

- **Validation skill expansion = preflight insurance**: Expanding validate-project-prefs to cover semantic correctness (not just syntax) gives operators a way to catch config errors before they hit production. This is required for Phase 2 to be trustworthy.

- **Dogfooding is fast confidence**: One real PR merge using Phase 2 on xgh itself surfaces ~80% of integration bugs and UX issues. It's 2–4 hours, not weeks, and it de-risks shipping to users.

- **Your users will dogfood anyway**: If you ship without dogfooding, the first user to merge a real PR on their codebase will find the integration bugs you could have found. You own the support debt. With dogfooding, you own the quality debt (which is cheaper).

**Recommend: Option (C). Ship hooks + tests + validation skill + real workflow validation. Confidence over speed.**
