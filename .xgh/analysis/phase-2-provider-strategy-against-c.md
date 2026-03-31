---
title: "Against Option (C): Why GitHub-Only with No Abstraction is Better"
analyst: AGAINST agent
date: 2026-03-25
context: Phase 2 hooks (PreToolUse, PostToolUse, PostToolUseFailure) implementation strategy
---

# Against Option (C) — GitHub-Only Implementation Without Abstraction

**Thesis**: Option (C)—GitHub-only code structured for "future provider abstraction"—combines the worst of both worlds: it adds abstraction complexity now (when only GitHub exists) without delivering the value. **Option (A)** (GitHub-only, zero abstraction) is the correct move.

---

## 1. Abstraction Tax on Code That Nobody Uses

Option (C) proposes building a provider abstraction layer *before* a second provider exists. This means:

- Designing interfaces for GitLab, Azure DevOps, Bitbucket that have **zero users**.
- Writing separate validation logic for each provider (PreToolUse hooks for different CLIs, different field mappings).
- Maintaining fallback/dispatch code that adds cognitive load on every hook edit.
- Testing multiple code paths in CI, even though only `github` runs in production.

**Reality check**: xgh has been in active development since Q1 2026. The preferences system supports 5 providers (`github|gitlab|bitbucket|azure-devops|generic`). To date, zero PRs add GitLab, Azure, or Bitbucket support. The `watch-prs` skill detects providers by URL pattern but doesn't actually implement multi-provider merge logic. This is called **YAGNI** — "You Aren't Gonna Need It."

When (if) a second provider actually lands, the abstraction can be added then—at minimal cost, because:
- All GitHub hooks will have shipped, so you know exactly what the abstraction must support.
- You can extract the abstraction from real working code, not guess at interfaces.
- You'll have real user feedback on what matters.

---

## 2. PreToolUse/PostToolUse are GitHub-Specific by Design

The Phase 2 hooks analysis identifies concrete implementations:

| Hook | Implementation | GitHub-only dependency |
|------|---|---|
| **PreToolUse** | Inject `--squash`/`--merge`/`--rebase` into `gh pr merge` commands | Directly reads `gh` CLI syntax |
| **PostToolUse** | Detect merge-method drift by parsing `gh pr merge` output | Parses GitHub's response format |
| **PostToolUseFailure** | Diagnose why `gh pr create` failed; suggest fixes like "credentials missing" | GitHub-specific error messages |

Adding a provider abstraction layer would require:
- Separate shell functions for each provider's CLI (e.g., `gitlab_pr_merge()`, `azure_pr_merge()`).
- Provider-specific error handling and flag injection.
- A provider-routing mechanism (already exists via URL detection, but would need to be wired into every hook).

This is **not a thin abstraction layer**—it's 3–5× the code for 0 users. The cost isn't paid back until user 2 shows up.

---

## 3. The Abstraction Won't Survive First Contact

Abstractions designed without users are almost always wrong:

- You'll guess that all providers have a "merge method" setting. GitLab does (`--squash`, `--ff`, etc.), but Azure DevOps has a different UX (you set policy on the branch itself, not the PR).
- You'll design a hook interface assuming all providers are CLI-based. Bitbucket Cloud is primarily API-driven; the CLI is minimal.
- You'll assume all providers store PR metadata the same way. They don't.

When the second provider arrives, the "abstraction" either:
1. **Gets thrown away** and replaced with something that actually fits both providers (sunk cost).
2. **Gets bent out of shape** to fit the new provider, making both code paths harder to read.

The pragmatic move is to ship GitHub-only code that is **simple and obvious**, then refactor to abstraction when you have two real examples.

---

## 4. xgh's Core Principle: Declarative Config, Not Polymorphism

xgh's mission is *"declarative AI ops"* — declare behavior in YAML, converge across platforms. Phase 2 hooks implement this by making `config/project.yaml` the single source of truth. The hooks don't need to be abstract; they need to be **correct for GitHub**.

If a GitLab user arrives and wants to use xgh:
- They create `config/project.yaml` with `provider: gitlab`.
- xgh tells them: "Phase 2 hooks are GitHub-only. To use them on GitLab, see [migration guide]. Contributors welcome."
- They either migrate to GitHub (xgh's natural home), contribute GitLab support, or build their own hooks.

This is honest and aligns with xgh's single-developer model. It's better than shipping a broken abstraction that pretends to support 5 providers but only works for 1.

---

## 5. Phase 2 Ships Faster as GitHub-Only

PreToolUse and PostToolUse are non-trivial:
- PreToolUse must read `config/project.yaml`, validate YAML, inject flags, and log modifications (none of this should be slow).
- PostToolUse must detect drift, emit audit logs, and avoid parsing errors on non-JSON tool responses.

Building this for GitHub is **6–8 weeks of careful implementation**. Building the same for 5 providers speculatively adds another **4–6 weeks** of design, testing, and provider-specific debugging.

**Option (A)**: Ship Phase 2 by April 2026, GitHub-only, rock-solid.
**Option (C)**: Ship Phase 2 by June 2026, with abstract provider interfaces that no one uses.

The opportunity cost is real. xgh has other Phase 2 work: dispatch system, skill improvements, trigger engine. GitHub-only unblocks that work 4–6 weeks earlier.

---

## Summary

Option (C) trades immediate complexity and slower delivery for speculative future benefit. **Option (A)** is the YAGNI answer: ship GitHub-only code that is simple, fast, and correct. If and when a second provider lands, extract the abstraction from real working code and real user needs.

**Recommend: Option (A). GitHub-only, zero abstraction.**
