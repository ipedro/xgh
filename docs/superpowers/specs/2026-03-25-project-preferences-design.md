# Project Preferences — Centralized Configuration for Skills

**Date:** 2026-03-25
**Status:** Draft
**Scope:** config/project.yaml integration, provider reference extraction, copilot-pr-review deprecation, preference capture convention

---

## Problem

PR workflow skills (`ship-prs`, `watch-prs`, `copilot-pr-review`, `review-pr`) independently auto-detect repo, probe Copilot policies, and hardcode reviewer defaults on every invocation. Provider-specific quirks documentation (GitHub, GitLab, Bitbucket, Azure DevOps) is duplicated across all three PR skills. None read from `config/project.yaml`, even though its `preferences:` section was designed as the project's preference registry.

Users must pass `--repo`, `--reviewer`, `--merge-method` on every call, or rely on per-skill auto-detection that re-probes APIs each time.

## Solution

1. Add a provider-agnostic `preferences.pr` section to `config/project.yaml`
2. Skills read defaults from project.yaml with a cascading read order
3. First invocation probes missing values and caches them back to project.yaml
4. Provider-specific documentation moves to shared references
5. `copilot-pr-review` is deprecated — its logic is absorbed into `ship-prs` and shared references
6. A preference capture convention teaches Claude to persist user statements to project.yaml
7. A validation skill enforces the convention

---

## Schema

```yaml
# config/project.yaml — new section under preferences:
preferences:
  pr:
    provider: github                      # github | gitlab | bitbucket | azure-devops
    repo: extreme-go-horse/xgh
    reviewer: copilot-pull-request-reviewer[bot]
    reviewer_comment_author: Copilot
    review_on_push: true
    merge_method: squash
    auto_merge: true
    branches:
      main:
        merge_method: merge
        required_approvals: 1
      develop:
        merge_method: squash
```

### Read order

For any field: **CLI flag > `branches.<base_ref>.<field>` > `preferences.pr.<field>` > auto-detect probe**

---

## Skill consumption pattern

### Shared helper: `lib/project-prefs.sh`

```bash
load_pr_pref() {
  local field="$1" cli_override="$2" branch="$3"

  # 1. CLI flag wins
  [[ -n "$cli_override" ]] && echo "$cli_override" && return

  # 2. Branch-specific override
  if [[ -n "$branch" ]]; then
    val=$(yq -r ".preferences.pr.branches.${branch}.${field} // empty" config/project.yaml 2>/dev/null)
    [[ -n "$val" ]] && echo "$val" && return
  fi

  # 3. Project default
  val=$(yq -r ".preferences.pr.${field} // empty" config/project.yaml 2>/dev/null)
  [[ -n "$val" ]] && echo "$val" && return

  # 4. Probe, cache, return
  val=$(probe_pr_field "$field")
  [[ -n "$val" ]] && cache_pr_pref "$field" "$val"
  echo "$val"
}
```

### Skills that change

| Skill | Change |
|-------|--------|
| `ship-prs` | Replace Step 0a (detect repo), 0c (probe reviewer), merge-method defaults with `load_pr_pref` calls. Replace inline provider profiles with `@references/providers/<provider>.md` |
| `watch-prs` | Same Step 0a/0c replacement |
| `copilot-pr-review` | **Delete.** Logic absorbed into ship-prs and shared references |
| `review-pr` | Read repo from project.yaml for `gh pr diff` calls |
| `pr-poller` agent | Receives values from dispatching skill (no change — dispatching skill now reads from project.yaml) |

---

## Probe-and-cache flow

When `preferences.pr` is empty or missing fields, the first skill invocation auto-populates:

| Field | Probe method |
|-------|-------------|
| `provider` | `git remote -v` → detect github.com / gitlab.com / bitbucket.org / dev.azure.com |
| `repo` | GitHub: `gh repo view --json nameWithOwner`; GitLab: `glab project view`; etc. |
| `reviewer` | GitHub: `gh api repos/$REPO/copilot/policies` → if enabled, set copilot bot; GitLab: check project approval rules; Others: leave empty, warn user |
| `merge_method` | Leave empty (skill defaults to squash if unset) |

### Write-back rules

- After probing, write discovered values to `config/project.yaml` using `yq -i`
- The file is tracked in git — user sees the change in `git diff` and can adjust before committing
- **Never overwrite:** If a field already has a value, probe skips it
- **CLI flags are ephemeral:** Override at runtime but don't write back
- **No TTL:** Values are stable (repo doesn't change, reviewer bot doesn't change). If the user switches providers, they edit project.yaml directly or delete the `pr:` block to re-probe

---

## Shared provider references

### New files

| File | Content |
|------|---------|
| `_shared/references/providers/github.md` | Copilot two-system distinction, reviewer list cycle, [bot] suffix rules, reviewer vs reviewer_comment_author mapping, review_on_push behavior, common errors |
| `_shared/references/providers/gitlab.md` | MR reviewers, approval rules, merge request API patterns |
| `_shared/references/providers/bitbucket.md` | PR reviewers, default reviewers, API patterns |
| `_shared/references/providers/azure-devops.md` | Required reviewers, policies, API patterns |

### Deleted files

| File | Reason |
|------|--------|
| `skills/copilot-pr-review/copilot-pr-review.md` | Absorbed into ship-prs + shared references |
| `commands/copilot-pr-review.md` | Command wrapper for deleted skill |

### What moves where

| Content | From | To |
|---------|------|----|
| Copilot two-system table | Inline in ship-prs, watch-prs, copilot-pr-review | `providers/github.md` |
| Reviewer list cycle | Inline in ship-prs, watch-prs, copilot-pr-review, pr-poller | `providers/github.md` |
| `[bot]` suffix rules | Inline in copilot-pr-review | `providers/github.md` |
| Provider profile blocks (GitLab, Bitbucket, Azure DevOps) | Inline in ship-prs, watch-prs | Respective `providers/*.md` files |

---

## Preference capture convention

### Shared reference: `_shared/references/preference-capture.md`

Teaches Claude to recognize declarative user statements about project preferences and persist them to `config/project.yaml`.

### Trigger patterns

| User says | Field written |
|-----------|--------------|
| "copilot reviews PRs automatically" | `pr.review_on_push: true` |
| "we squash merge everything" | `pr.merge_method: squash` |
| "releases to main use merge commits" | `pr.branches.main.merge_method: merge` |
| "we need 2 approvals on main" | `pr.branches.main.required_approvals: 2` |
| "don't auto-merge, I want to review first" | `pr.auto_merge: false` |
| "use opus for code review" | `superpowers.review_model: opus` |

### Confirm-before-write flow

```
User: "we always squash to develop"
Claude: "I'll save that as your default merge method for develop."
→ writes preferences.pr.branches.develop.merge_method: squash
→ shows: "Updated config/project.yaml — pr.branches.develop.merge_method: squash"
```

### Where things go

| Type | Destination |
|------|------------|
| Runtime preferences (reviewer, merge method, models, effort) | `config/project.yaml` |
| Development process rules (TDD, branch strategy, test conventions) | `AGENTS.md` |
| Personal preferences (communication style, response length) | Memory system |

---

## Validation skill

Local skill at `~/.claude/skills/validate-project-prefs.md`.

### Checks

| Check | Pattern | Location |
|-------|---------|----------|
| Hardcoded reviewer logins | `copilot-pull-request-reviewer` outside `_shared/references/providers/` | Fail |
| Hardcoded repo detection | `gh repo view --json nameWithOwner` outside `lib/project-prefs.sh` | Fail |
| Inline provider profiles | `reviewer_bot:` / `reviewer_comment_author:` blocks outside `_shared/references/providers/` and `project.yaml` | Fail |
| Missing project.yaml read | Skill mentions `--repo`, `--reviewer`, or `--merge-method` but doesn't reference `load_pr_pref` or `project.yaml` | Warn |

### Output

Pass/fail table with file:line references.

---

## AGENTS.md update

New section under **Development Guidelines**:

```markdown
### Project preferences (`config/project.yaml`)

Skills MUST read runtime defaults from `config/project.yaml` under `preferences:`.
Never hardcode reviewer logins, repo names, merge methods, or provider-specific
values in skill files.

- **Read order:** CLI flag > branch override > project default > auto-detect probe
- **Probe-and-cache:** First invocation discovers missing values and writes them
  back to project.yaml. Subsequent runs read directly.
- **Provider quirks:** Live in `skills/_shared/references/providers/<provider>.md`,
  not inline in skills.
- **Preference capture:** When a user states a project preference, confirm and
  write to project.yaml. Show the diff. Don't silently assume.
- **Validation:** Run the validate-project-prefs skill to check compliance.
```

---

## Summary of changes

| Action | Files |
|--------|-------|
| **Modify** | `config/project.yaml` (add `preferences.pr`), `skills/ship-prs/ship-prs.md`, `skills/watch-prs/watch-prs.md`, `skills/review-pr/review-pr.md`, `agents/pr-poller.md`, `AGENTS.md` |
| **Create** | `lib/project-prefs.sh`, `skills/_shared/references/providers/github.md`, `providers/gitlab.md`, `providers/bitbucket.md`, `providers/azure-devops.md`, `skills/_shared/references/preference-capture.md`, `~/.claude/skills/validate-project-prefs.md` |
| **Delete** | `skills/copilot-pr-review/copilot-pr-review.md`, `commands/copilot-pr-review.md` |
