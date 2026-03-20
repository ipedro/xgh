# xgh — Feature Ideas Backlog

Unordered ideas for future features and improvements.

---

## 1. GitHub provider (bash mode)

Currently GitHub is listed as a provider spec but the bash fetch is incomplete. Pull PRs, Actions runs, security alerts, discussions, and releases into the retrieval pipeline as a proper `mode: bash` provider alongside Slack/Jira.

---

## 2. `/xgh-standup`

Generate a daily standup from recent activity: what moved in Jira, what PRs were opened/merged, what decisions were made. Output a ready-to-paste 3-section summary (done / doing / blocked).

---

## 3. `/xgh-pr-review`

Given a PR URL: fetch the diff, look up the Jira ticket, retrieve related Slack threads, check conventions in the context tree, and produce a structured review with context the reviewer would otherwise miss.

---

## 4. Delta briefing

`/xgh-brief` currently always runs everything. Add a `--since` flag (or auto-detect last brief timestamp) to only surface items that changed since the last brief. Skip the noise on frequent invocations.

---

## 5. Slack thread depth

When retrieve finds a Slack message with a link, follow the full thread (not just the first message). Right now retrieval is shallow. Full thread context catches the decision/resolution at the bottom of the thread.

---

## 6. `/xgh-timeline`

Given a project and date range, produce a chronological event feed across all providers: Slack decisions, Jira status changes, PR merges, Figma updates. Useful for retrospectives and incident postmortems.

---

## 7. Fix pre-existing test failures

`test-plan4-integration.sh` (20 fails), `test-multi-agent.sh` (2 fails), `test-brief.sh`/`test-briefing.sh` (`XGH_BRIEFING` missing). These mask real regressions. A clean test suite is worth more than 10 new features.

---

## 8. Provider failure recovery

When a bash provider's `fetch.sh` exits non-zero, log the error but don't abort the whole retrieve cycle. Currently a single provider failure can silently kill the run. Should be log-and-continue.

---

## 9. Inbox aging

Items in `~/.xgh/inbox/` that are older than N hours but unprocessed should have their `urgency_score` bumped automatically. Right now staleness isn't factored in until analyze runs, so old items can stay deprioritized indefinitely.

---

## 10. `/xgh-release-notes`

Given a Jira fix version or a date range: pull all closed tickets, merged PRs, and relevant Slack decisions. Synthesize a changelog grouped by category (features, fixes, infra). Useful right before a release cut.

---

*Added: 2026-03-20*
