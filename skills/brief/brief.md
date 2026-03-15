---
name: xgh:briefing
description: >
  Morning/session briefing skill. Checks Slack, Jira, and GitHub for urgent
  items and produces a structured, actionable summary before the user starts
  work. Invoked by /xgh-briefing or automatically by the SessionStart hook
  when XGH_BRIEFING=1.
type: flexible
triggers:
  - when the user runs /xgh-briefing
  - when the SessionStart hook detects XGH_BRIEFING=1
  - when the user says "brief me", "what's up", "morning briefing", or similar
---

# xgh:briefing — Session Briefing

Produce a structured session briefing by checking available data sources
(Slack, Jira, GitHub) and summarising what needs attention right now.

## Step 1 — Detect available MCPs

Before gathering data, check which integrations are active this session.
Refer to `xgh:mcp-setup` for setup help if any are missing.

| Integration | Detection signal | Capability |
|-------------|-----------------|------------|
| Slack | `slack_read_channel` / `slack_search_public` tool available | DMs, mentions, channel alerts |
| Jira | `getJiraIssue` / `searchJiraIssuesUsingJql` tool available | Tickets assigned to you, blockers |
| GitHub | `gh` CLI available (`command -v gh`) | PRs awaiting review, CI failures |
| Cipher | `cipher_memory_search` tool available | Past context, ongoing threads |

Build a source status line:

```
[Sources checked: Slack ✓/✗ · Jira ✓/✗ · GitHub ✓/✗]
```

Use ✓ for each source that is available and queried, ✗ for unavailable ones.

## Step 2 — Gather data (parallel where possible)

Query all available sources simultaneously:

### Slack (if available)
- Unread DMs or @-mentions since last session
- Any `#incidents`, `#alerts`, or `#on-call` channel activity
- Messages directed at the user by name or handle

### Jira (if available)
- Issues assigned to the user with status "In Progress" or "To Do"
- Issues where the user is mentioned in comments within the last 24 h
- Blockers or PRs waiting on the user

### GitHub (if available)
- Pull requests authored by the user: open, draft, needs-review
- Pull requests from teammates requesting review from the user
- CI failures on the user's branches

### Cipher memory (if available)
- Recent session context or unresolved threads
- Any "revisit" or "follow-up" notes stored by previous sessions

## Step 3 — Classify items

Place each item into exactly one category:

| Category | Criteria |
|----------|----------|
| **NEEDS YOU NOW** | Blocking another person; urgent Slack message; CI on fire; PR review explicitly requested today |
| **IN PROGRESS** | Tickets/PRs the user is actively working on |
| **INCOMING** | Items assigned but not yet started; new tickets; pending reviews not yet urgent |
| **TEAM PULSE** | FYI updates from teammates; non-urgent channel activity; standup notes |
| **TODAY** | Calendar items, scheduled deployments, sprint ceremonies (if inferable from Jira/Slack) |

## Step 4 — Produce the briefing

Output the briefing using **exactly** this format. Do not omit sections even if
they have no items — use `(nothing)` for empty sections.

```
🐴🤖 Session Briefing — [Day, Date Time]
[Sources checked: Slack ✓ · Jira ✓ · GitHub ✓]

━━ NEEDS YOU NOW ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[items or (nothing)]

━━ IN PROGRESS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[items or (nothing)]

━━ INCOMING ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[items or (nothing)]

━━ TEAM PULSE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[items or (nothing)]

━━ TODAY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[items or (nothing)]

━━ SUGGESTED FOCUS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[one recommendation — the single highest-value thing to work on next]

Proceed? [Y] or tell me what you want to work on instead.
```

### Item format

Each item in a section should be one line:

```
• [SOURCE] Short description — link or ticket ID if available
```

Examples:
```
• [Slack] @alice is blocked on your PR review — #eng-backend
• [Jira] XGH-42 "Add dark mode" — In Progress, last updated 2 days ago
• [GitHub] PR #87 "Fix auth bug" — 2 approvals, CI green, ready to merge
```

## Step 5 — Await user response

After printing the briefing, wait. The user will:

- Type `Y` or press Enter to proceed with the Suggested Focus
- Describe a different task → switch to that task immediately
- Ask a follow-up question → answer it before proceeding

## Degraded mode (no MCPs available)

If no external MCPs are configured and GitHub CLI is also absent, output:

```
🐴🤖 Session Briefing — [Day, Date Time]
[Sources checked: no integrations available]

No data sources are connected. To enable the full briefing, run /xgh-setup
to configure Slack, Jira, and/or GitHub integrations.

What would you like to work on today?
```

## Error handling

- If a source times out or returns an error, mark it ✗ in the header and skip it
- Never fail the entire briefing because one source is unavailable
- Log skipped sources at the bottom: `(Slack unavailable — skipped)`

## Composability

This skill is invoked by:
- `/xgh-briefing` command (direct user invocation)
- `session-start.sh` hook when `XGH_BRIEFING=1` is set in the environment
- Other skills that want to surface a briefing mid-session (rare)

After this skill completes, control returns to the user or the calling context.
