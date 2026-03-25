# Preference Capture Convention

When a user states a project preference, confirm and write it to `config/project.yaml`.

## Trigger Patterns

| User says | Field written |
|-----------|--------------|
| "copilot reviews PRs automatically" | `pr.review_on_push: true` |
| "we squash merge everything" | `pr.merge_method: squash` |
| "releases to main use merge commits" | `pr.branches.main.merge_method: merge` |
| "we need 2 approvals on main" | `pr.branches.main.required_approvals: 2` |
| "don't auto-merge, I want to review first" | `pr.auto_merge: false` |
| "use opus for code review" | `superpowers.review_model: opus` |

## Confirm-Before-Write Flow

```
User: "we always squash to develop"
Claude: "I'll save that as your default merge method for develop."
→ writes preferences.pr.branches.develop.merge_method: squash
→ shows: "Updated config/project.yaml — pr.branches.develop.merge_method: squash"
```

Always confirm the write. Show the field path and value. Never silently assume.

## Where Things Go

| Type | Destination |
|------|------------|
| Runtime preferences (reviewer, merge method, models, effort) | `config/project.yaml` |
| Development process rules (TDD, branch strategy, test conventions) | `AGENTS.md` via `config/team.yaml` |
| Personal preferences (communication style, response length) | Memory system |

Do not write development process rules to `config/project.yaml`. Do not write runtime preferences to `AGENTS.md`.
