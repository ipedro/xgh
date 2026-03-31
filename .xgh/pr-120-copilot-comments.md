# PR 120 Copilot Comments Summary

Copilot Review: COMMENTED (not APPROVED) with 8 inline comments
Baseline: 0 → 8 comments (all new)

## Comments requiring fixes:

1. **line 794, .xgh/plans/2026-03-25-project-preferences-impl.md**
   - "CI currently runs a hardcoded matrix of `bash tests/<name>.sh` (see `.github/workflows/ci.yml`)"
   - Action: Need to fix CI hardcoding reference

2. **line 132, lib/config-reader.sh**
   - "`cache_pr_pref` rewrites `config/project.yaml` automatically during `load_pr_pref` probing. This sil[ent side effect]"
   - Action: Silent modification concern; needs explicit handling or documentation

3. **line 110, lib/config-reader.sh**
   - "`probe_pr_field` uses pipelines/command substitutions (`glab ... | python3 ...`, `gh api ... | pytho[n3]`)"
   - Action: Command pipeline parsing concern; needs robustness review

4. **line 92, lib/config-reader.sh**
   - "Provider auto-detection in `probe_pr_field provider` dropped patterns that were previously documente[d]"
   - Action: Missing pattern detection logic; needs restoration or documentation

5. **line 29, skills/ship-prs/ship-prs.md**
   - "The Defaults section still hardcodes `--merge-method merge`, but the skill now loads `merge_method`"
   - Action: Inconsistent defaults between doc and code

6. **line 40, skills/watch-prs/watch-prs.md**
   - "This points readers to the GitHub provider reference unconditionally, but `PROVIDER` may be gitlab/b[itbucket]"
   - Action: Provider-specific docs should be conditional

7. **line 23, skills/review-pr/review-pr.md**
   - "The instructions use `$REPO` in `gh pr list`/`gh pr diff`, but this skill doesn't show where `REPO` [is defined]"
   - Action: Missing documentation of `$REPO` variable

8. **line 3, skills/_shared/references/providers/github.md**
   - "This file says it's referenced by `pr-poller`, but `agents/pr-poller.md` doesn't currently reference[it]"
   - Action: Cross-reference documentation inconsistency

## Classification:
- Hardcoding cleanup: #1, #5
- Logic/robustness concerns: #2, #3, #4
- Documentation/reference gaps: #6, #7, #8

All require **sonnet-level fixes** (architecture/logic). Dispatch sonnet agent.
