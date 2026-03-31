# Phase 2.2 Drift Detection: FOR Agent Argument (Option B)

**Role:** Advocate for Option B — diff-aware drift detection that identifies WHICH preference fields changed.

---

## The Case for Option (B)

### 1. **Actionability: Diff Reveals Intent**

Option A ("file changed") is useless in a multi-hook environment. When `project.yaml` is modified:
- Did the user's `/xgh-save-preferences` skill apply pending prefs? (expected)
- Did a manual git edit break schema? (error)
- Did an unrelated skill write to an adjacent domain? (spillover)
- Did a parallel agent's config write collide with mine? (conflict)

Only a diff answers *which field changed and why*. This is especially critical because Phase 1 explicitly rejects auto-write (by design) and requires explicit `/xgh-save-preferences` to promote staging area changes. If drift detection cannot distinguish "expected convergence" (pr.merge_method changed from default to squash) from "unexpected collision" (vcs.default_branch silently reset), operators have no way to audit whether preferences converged correctly or drifted.

In a system where **explicit apply is the trust model**, drift detection without diff-awareness is a compliance theater.

---

### 2. **Implementation Complexity: Negligible Addition**

Option B adds ~20 lines over Option A:
- Option A: `if [[ -f config/project.yaml ]]; then log "config/project.yaml modified"; fi`
- Option B: `diff <(yq . config/project.yaml 2>/dev/null) <(git show HEAD:config/project.yaml 2>/dev/null) | grep -E '^[<>]' | awk '{print $2}' | sort -u`

The `yq` YAML parser is already a Phase 1 dependency (config-reader.sh uses it). Comparing structured YAML diffs is actually *simpler* than comparing raw files because YAML structure is stable (no whitespace false positives). The cost is sub-millisecond—PostToolUse is a rare hook, not on the hot path like PreToolUse.

---

### 3. **Value Justifies Minimal Overhead**

Phase 1 design (eval-1.md Section 4) identifies the Stop hook's reminder as the mechanism for surfacing pending preferences:

> *"The Stop hook fires once per session if pending preferences exist. Strengthen this: the reminder should include a one-line summary of WHAT changed (e.g., '3 pending preferences: pr.merge_method, pr.reviewer, vcs.default_branch'), not just that something is pending."*

This is **option B's exact use case**. Without a diff, the Stop hook reminder is incomplete—it says "3 pending preferences" but doesn't tell the user whether they've already been applied or are still pending. The user must open the staging file to audit, defeating the point of a one-shot reminder.

Additionally, the PostToolUse guard for deliberate `config/project.yaml` edits (eval-1.md S2) *requires* diff awareness to distinguish "user manually edited" from "hook auto-wrote" (which shouldn't happen). Without a diff, the guard fires on every edit, creating noise.

---

## Summary: 3-4 Bullets

- **Actionability gap:** Option A leaves operators unable to distinguish expected preference convergence from unexpected drift or collisions in a multi-domain, multi-hook environment. Only diffs answer "which field changed and was it expected?"

- **Minimal cost:** Parsing structured YAML diffs adds ~20 lines and sub-millisecond latency to a non-hot-path hook (PostToolUse fires rarely, not on every tool call). The `yq` dependency already exists from Phase 1.

- **Closes design gaps:** Phase 1's eval document explicitly recommends diff-aware Stop hook reminders and PostToolUse guards for unauthorized edits. Option B enables both; Option A blocks both.

- **Trust model requirement:** Phase 1's core insight is "explicit apply, no auto-write." Without diff-aware detection, the system cannot audit whether explicit applies succeeded or drifted. It becomes a declaration of intent with no way to verify execution.

---

## Next Steps

Option B enables:
1. **Audit trail** — session logs include which fields actually converged
2. **Stop hook reminder** — "3 preferences changed: pr.merge_method, pr.reviewer, pr.auto_merge" instead of generic "preferences pending"
3. **Edit guard** — distinguish legitimate manual edits from hook noise
4. **Operator confidence** — "I see what changed, I see it's what I intended to change, I'm ready to commit"

The overhead is negligible. The value is foundational to Phase 2.2's coherence.
