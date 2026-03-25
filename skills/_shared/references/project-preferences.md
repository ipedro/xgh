# Project Preferences Reference

Skills can read `config/project.yaml` at dispatch time to pick up project-level defaults
without relying on AGENTS.md.

## Reading preferences (Python, stdlib only)

```python
import yaml, os
prefs = {}
if os.path.exists("config/project.yaml"):
    with open("config/project.yaml") as f:
        cfg = yaml.safe_load(f) or {}
    prefs = cfg.get("preferences", {})
```

## Key preference blocks

| Block | Keys | Used by |
|-------|------|---------|
| `dispatch` | `default_agent`, `fallback_agent`, `exec_effort`, `review_effort` | `/xgh-dispatch` cold-start defaults |
| `pair_programming` | `enabled`, `tool`, `effort`, `phases` | pair-programming skills |
| `superpowers` | `implementation_model`, `review_model`, `effort` | superpowers dispatch |
| `design` | `model`, `effort` | `/xgh-design` |
| `agents` | `default_model` | agent frontmatter with `model: inherit` |
| `pr` | `provider`, `repo`, `reviewer`, `reviewer_comment_author`, `merge_method`, `review_on_push`, `auto_merge`, `branches` | `/xgh-ship-prs`, `/xgh-watch-prs`, `/xgh-review-pr` |

## Priority order

Each preference domain defines its own priority order.

**Default:** User override at call time → profile data (`model-profiles.yaml`) → **project preferences** → CLI defaults

**PR domain:** CLI flag → `branches.<base_ref>.<field>` → `preferences.pr.<field>` → auto-detect probe

Skills MUST respect these orders. Never let project preferences override an explicit user flag.

## PR preferences helper

PR skills use `load_pr_pref` from `lib/config-reader.sh` instead of raw Python:

```bash
source lib/config-reader.sh
REPO=$(load_pr_pref repo "$CLI_REPO" "")
MERGE_METHOD=$(load_pr_pref merge_method "$CLI_MERGE_METHOD" "$BASE_BRANCH")
MERGE_METHOD="${MERGE_METHOD:-squash}"  # fallback — merge_method is not probed
```
