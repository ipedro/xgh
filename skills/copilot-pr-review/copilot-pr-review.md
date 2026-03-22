---
name: xgh:copilot-pr-review
description: >
  Manage GitHub Copilot PR code reviews. Request, re-review, check status,
  list comments, reply, and delegate. Encodes all Copilot API pitfalls
  (bot suffix, delegation vs review, re-review cycle).
type: rigid
triggers:
  - when the user runs /xgh-copilot-pr-review
  - when the user says "copilot review", "request copilot review", "re-review", "copilot status"
  - when an agent needs to interact with Copilot PR reviews
---

> **Output format:** Start with `## 🐴🤖 xgh copilot-pr-review`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status.

# /xgh-copilot-pr-review — Copilot PR Review Manager

Manage GitHub Copilot's PR code review bot safely from the CLI. Encodes all known API pitfalls so you never accidentally trigger the SWE delegation agent or hit silent failures.

## ⚠️ Critical: Two Copilot Systems

GitHub has two **completely separate** Copilot integrations for PRs. Confusing them causes unwanted sub-PRs.

| System | Trigger | What it does |
|--------|---------|-------------|
| **Code Review** | Add `copilot-pull-request-reviewer[bot]` to reviewer list | Leaves inline review comments |
| **SWE Agent** | Tag `@copilot` in a PR comment | Opens a **new PR** with implementation changes |

This skill uses the **Code Review** system by default. The `delegate` subcommand explicitly opts into the SWE Agent with a safety gate.

**🚫 NEVER tag `@copilot` in PR comments or replies.** Not for questions, not for clarification, not for anything. Every `@copilot` mention triggers the SWE agent to open a new PR. Copilot does NOT read or respond to replies on its review comments — it is a one-way reviewer. If you want it to look again, use `re-review`.

## Usage

```
/xgh-copilot-pr-review <command> <PR> [args] [--repo owner/repo]
```

## Step 0 — Detect repo

If `--repo` is provided, use it. Otherwise auto-detect:

```bash
REPO=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/](.+/.+?)(\.git)?$|\1|')
```

If auto-detect fails, print: `❌ Could not determine repo. Use --repo owner/repo`

## Commands

Parse the first argument as the subcommand and the second as the PR number, matching the `<command> <PR>` usage signature. If no subcommand is given, default to `status`.

---

### `request <PR>` — Request Copilot review

Add Copilot as a reviewer for the first time.

**Step 1 — Check if already requested:**
```bash
gh api repos/$REPO/pulls/$PR/requested_reviewers \
  --jq '.users[] | select(.login == "copilot-pull-request-reviewer[bot]") | .login'
```

If Copilot is already in the list, print: `ℹ️ Copilot already requested for review on PR #$PR`

**Step 2 — Check if already reviewed:**
```bash
gh api repos/$REPO/pulls/$PR/reviews \
  --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | length'
```

If already reviewed, print: `ℹ️ Copilot has already reviewed PR #$PR. Use re-review to request another pass.`

**Step 3 — Request review:**
```bash
gh api repos/$REPO/pulls/$PR/requested_reviewers \
  -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

**Output:**
```
## 🐴🤖 xgh copilot-pr-review

✅ Copilot review requested for PR #$PR in $REPO
```

---

### `re-review <PR>` — Trigger re-review after fixes

Remove and re-add Copilot as reviewer to trigger a fresh review.

**Step 1 — Try gh pr edit (preferred):**

> Note: `gh pr edit` uses GraphQL and works **without** the `[bot]` suffix. The `[bot]` suffix is only required for the REST API (see Step 2).

```bash
gh pr edit $PR --repo $REPO --remove-reviewer copilot-pull-request-reviewer
gh pr edit $PR --repo $REPO --add-reviewer copilot-pull-request-reviewer
```

**Step 2 — If gh pr edit fails, fall back to REST API:**
```bash
gh api repos/$REPO/pulls/$PR/requested_reviewers \
  -X DELETE -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
gh api repos/$REPO/pulls/$PR/requested_reviewers \
  -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

**Step 3 — If both fail, print manual instructions:**
```
❌ Could not re-request review. Try manually:
   gh pr edit $PR --repo $REPO --remove-reviewer copilot-pull-request-reviewer
   gh pr edit $PR --repo $REPO --add-reviewer copilot-pull-request-reviewer
```

**Output on success:**
```
## 🐴🤖 xgh copilot-pr-review

✅ Copilot re-review requested for PR #$PR in $REPO
```

---

### `status <PR>` — Check Copilot review state

**Step 1 — Get last review:**
```bash
gh api repos/$REPO/pulls/$PR/reviews \
  --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | last | {state: .state, submitted_at: .submitted_at}'
```

**Step 2 — Count comments:**
```bash
gh api repos/$REPO/pulls/$PR/comments \
  --jq '[.[] | select(.user.login == "Copilot")] | length'
```

**Step 3 — Check pending:**
```bash
gh api repos/$REPO/pulls/$PR/requested_reviewers \
  --jq '[.users[] | select(.login == "copilot-pull-request-reviewer[bot]")] | length'
```

**Output:**
```
## 🐴🤖 xgh copilot-pr-review — status

| Field        | Value                        |
|--------------|------------------------------|
| PR           | #$PR                         |
| Repo         | $REPO                        |
| Review state | $STATE (or — if none)        |
| Last review  | $SUBMITTED_AT (or — if none) |
| Comments     | $COUNT                       |
| Pending      | ✅ requested / —             |
```

---

### `comments <PR>` — List Copilot's inline comments

**Step 1 — Fetch comments:**
```bash
gh api repos/$REPO/pulls/$PR/comments \
  --jq '[.[] | select(.user.login == "Copilot")] | .[] | {id: .id, path: .path, line: .line, body: .body[0:200]}'
```

**Output:**
```
## 🐴🤖 xgh copilot-pr-review — comments

| ID | File | Line | Comment |
|----|------|------|---------|
| $ID | $PATH | $LINE | $BODY (truncated to 200 chars) |
...

$COUNT comment(s) from Copilot on PR #$PR
```

If no comments: `ℹ️ No Copilot comments found on PR #$PR`

---

### `reply <PR> <comment_id> "<message>"` — Reply to a Copilot comment

**⚠️ Safety: strip @copilot from the message to prevent accidental delegation.**

**Step 1 — Sanitize message:**
Remove any occurrence of `@copilot` from the message body.

**Step 2 — Post reply:**
```bash
gh api repos/$REPO/pulls/comments/$COMMENT_ID/replies \
  -X POST -f "body=$SANITIZED_MESSAGE"
```

**Output:**
```
## 🐴🤖 xgh copilot-pr-review

✅ Replied to comment $COMMENT_ID on PR #$PR
```

If the original message contained `@copilot`, also print:
```
⚠️ Stripped @copilot from your message to prevent triggering delegation mode.
```

---

### `delegate <PR> "<instructions>"` — Invoke Copilot SWE Agent

**⚠️ This triggers the SWE agent, which opens a NEW PR with implementation changes.**

**Step 1 — Safety gate (unless --yes is passed):**

Print:
```
⚠️  WARNING: This will trigger Copilot SWE agent to open a NEW PR.
This is delegation mode, NOT code review.

PR: #$PR in $REPO
Instructions: "$INSTRUCTIONS"

Proceed? [y/N]
```

If user does not confirm, abort.

Agents can pass `--yes` to skip the prompt.

**Step 2 — Post comment:**
```bash
gh api repos/$REPO/issues/$PR/comments \
  -X POST -f "body=@copilot $INSTRUCTIONS"
```

Note: Uses `/issues/` endpoint (not `/pulls/`) because PR comments are issue comments.

**Output:**
```
## 🐴🤖 xgh copilot-pr-review

✅ Delegated to Copilot SWE agent on PR #$PR
⚠️ Watch for a new PR to appear — Copilot will open one with its changes.
```

---

## Known Pitfalls Reference

These are encoded into the skill's logic, but listed here for reference:

| Pitfall | Detail |
|---------|--------|
| `[bot]` suffix required | `reviewers[]=copilot-pull-request-reviewer` (no `[bot]`) returns 422. `reviewers[]=Copilot` silently fails (0 reviewers). |
| `@copilot` = delegation | Tagging in comments opens new PRs, not re-reviews. NEVER tag for questions — Copilot doesn't read replies. |
| Comment author ≠ reviewer login | Comments come from `Copilot`, reviewer is `copilot-pull-request-reviewer[bot]` — filter accordingly. |
| Can't dismiss COMMENTED reviews | Copilot always leaves COMMENTED state; dismiss API returns 422 for non-APPROVE/CHANGES_REQUESTED. |
| Re-review requires DELETE + POST | Just POST alone doesn't re-trigger if Copilot already reviewed. |
| DELETE may 422 on bot node ID | `gh api ... -X DELETE -f 'reviewers[]=copilot-pull-request-reviewer[bot]'` can return 422 with "Could not resolve to User node". Use `gh pr edit --remove-reviewer` instead, which works reliably. |
| `gh pr edit` works without `[bot]` | `gh pr edit --add-reviewer copilot-pull-request-reviewer` (no `[bot]`) works via GraphQL. The `[bot]` suffix is only required for the REST API. |
| `gh pr edit --add-reviewer Copilot` fails | GraphQL error "Could not resolve user". Must use `copilot-pull-request-reviewer` (the full bot login sans `[bot]`). |
| Reviews on unrelated files | Copilot reviews ALL files in the diff, including pre-existing artifacts not introduced by the PR. It may comment on files you didn't change. Reply explaining they're out of scope. |
| Custom instructions | `.github/copilot-instructions.md` (4000 char limit, reads from **base branch**, not PR branch). |
| Path-specific instructions | `.github/instructions/**/*.instructions.md` |
| Quota | Each review costs 1 premium request per review cycle. |
| Review latency | Reviews typically take <30 seconds, but re-review requests may take several minutes. Don't re-request too aggressively. |

## Error Handling

| Error | Detection | Message |
|-------|-----------|---------|
| Invalid PR | API returns 404 | `❌ PR #$PR not found in $REPO` |
| Not authorized | API returns 403 | `❌ Not authorized. Run: gh auth status` |
| Rate limited | API returns 429 | `⚠️ Rate limited. Retry after $SECONDS seconds.` |
| Repo auto-detect fails | git command fails | `❌ Could not determine repo. Use --repo owner/repo` |
