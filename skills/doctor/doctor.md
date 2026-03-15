---
name: xgh:ingest-doctor
description: >
  Pipeline health check. Validates config completeness, Slack/Jira/Qdrant/Cipher
  connectivity, scheduler freshness, workspace stats, and codebase index status.
  Outputs a structured ✓/✗ report with fix suggestions.
type: rigid
triggers:
  - when the user runs /xgh-doctor
  - when the user says "check ingest", "health check", "is the pipeline running"
---

# xgh:ingest-doctor — Pipeline Health Check

Run all checks and output a structured report. Use `✓` for pass, `✗` for fail.

## Check 1 — Config

- `~/.xgh/ingest.yaml` exists and parses: `python3 -c "import yaml; yaml.safe_load(open('...'))" 2>&1`
- Required fields present: `profile.name`, `profile.slack_id`, `profile.platforms`
- At least one active project under `projects:`
- `cipher.workspace_collection` is set

## Check 2 — Connectivity

For each active project:
- Each Slack channel: `slack_search_channels` to verify accessible
- Each Jira key: `getJiraIssue` with a simple query to verify it resolves

Qdrant: `curl -sf http://localhost:6333/healthz` via Bash — show URL from `cipher.yml`

Cipher MCP: test with `cipher_memory_search` using query `"xgh health check"` — verify it returns without error

## Check 3 — Pipeline freshness

Check `~/.xgh/logs/retriever.log` for last timestamp (last line matching ISO date):
- < 10 min ago: ✓ healthy
- 10–30 min ago: ⚠ warn
- > 30 min ago: ✗ overdue

Check `~/.xgh/logs/analyzer.log` similarly:
- < 45 min: ✓ | 45–90 min: ⚠ | > 90 min: ✗

## Check 4 — Scheduler

macOS: `launchctl list 2>/dev/null | grep "com.xgh"` — show loaded/unloaded per agent
Linux: `crontab -l 2>/dev/null | grep "xgh"` — show installed entries

## Check 5 — Workspace stats

Query Qdrant collection stats:
```bash
curl -sf "${QDRANT_URL}/collections/${WORKSPACE_COLLECTION}"
```
Show: exists ✓/✗, vector count, approximate size.

## Check 6 — Codebase index

For each project with `github:` entries, check `index.last_full` against `index.schedule`:
- Never indexed: ✗ (suggest `/xgh-index-repo`)
- Overdue per schedule: ⚠
- Current: ✓

## Output format

```
xgh Ingest Health Check
═══════════════════════

Config
  ✓ ~/.xgh/ingest.yaml exists and parses
  ✓ Profile: [name] ([role], [squad])
  ✓ 2 active projects configured

Connectivity
  ✓ Slack: #channel-1 accessible
  ✗ Slack: #channel-missing — not found (check channel name in ingest.yaml)
  ✓ Jira: PTECH-31204 exists (23 open issues)
  ✓ Qdrant: localhost:6333 responding
  ✓ Cipher MCP: responding

Pipeline
  ✓ Retriever: last run 3 min ago (healthy)
  ✗ Analyzer: last run 52 min ago (overdue — threshold: 45 min)

Scheduler
  ✓ com.xgh.retriever: loaded
  ✓ com.xgh.analyzer: loaded

Workspace
  ✓ Collection "xgh-workspace" exists (142 vectors)

Codebase Index
  ✓ acme-ios: indexed 2 days ago (schedule: weekly — OK)
  ✗ passcode-service: never indexed — run /xgh-index-repo

Summary: 9 passed, 0 warnings, 2 failures
Fix: Check #channel-missing name. Run: claude -p "/xgh-analyze" to clear overdue analyzer.
```
