---
name: xgh:validate-project-prefs
description: "Use when checking that skills read PR workflow values from config/project.yaml instead of hardcoding reviewer logins, repo names, or merge methods."
---

# xgh:validate-project-prefs — Preference Compliance Checker

Scan skill files for hardcoded PR workflow values that should be read from `config/project.yaml`.

## Checks

Run these grep patterns against `skills/` (excluding `_shared/references/providers/` and this skill):

### 1. Hardcoded reviewer logins

```bash
grep -rn "copilot-pull-request-reviewer" skills/ --include="*.md" \
  | grep -v "_shared/references/providers/" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches. **Fail:** list file:line for each match.

### 2. Hardcoded repo detection

```bash
grep -rn "gh repo view --json nameWithOwner" skills/ --include="*.md" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches (should use `load_pr_pref repo`). **Fail:** list file:line.

### 3. Inline provider profiles

```bash
grep -rn "reviewer_bot:" skills/ --include="*.md" \
  | grep -v "_shared/references/providers/" \
  | grep -v "validate-project-prefs"
```
**Pass:** no matches. **Fail:** list file:line.

### 4. Missing project.yaml read (warning only)

For skills that mention `--repo`, `--reviewer`, or `--merge-method` in their usage:
```bash
for skill in skills/ship-prs/ship-prs.md skills/watch-prs/watch-prs.md skills/review-pr/review-pr.md; do
  if ! grep -q "load_pr_pref\|project\.yaml" "$skill"; then
    echo "WARN: $skill mentions PR flags but does not reference load_pr_pref or project.yaml"
  fi
done
```

## Output format

```
## 🐴🤖 xgh validate-project-prefs

| Check | Status | Details |
|-------|--------|---------|
| Hardcoded reviewer logins | ✅ / ❌ | file:line matches |
| Hardcoded repo detection | ✅ / ❌ | file:line matches |
| Inline provider profiles | ✅ / ❌ | file:line matches |
| Missing project.yaml read | ✅ / ⚠️ | skill files without reference |
```
