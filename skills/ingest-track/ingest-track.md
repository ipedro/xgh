---
name: xgh:ingest-track
description: >
  Interactive project onboarding. Prompts for Slack channels, Jira, Confluence, Figma,
  and GitHub refs, validates connectivity, runs initial backfill of recent Slack history,
  and appends the project to ~/.xgh/ingest.yaml.
type: flexible
triggers:
  - when the user runs /xgh-track
  - when the user says "add project", "track project", "monitor new project"
mcp_dependencies:
  - mcp__claude_ai_Slack__slack_search_channels
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__getConfluencePage
---

# xgh:ingest-track — Project Onboarding

Interactive skill to add a new project to xgh monitoring. Ask one question at a time.

## Step 1 — Collect project details

Ask each question below separately. Validate before moving to the next.

1. **Project name** — free text. Derive config key: lowercase, spaces → hyphens, no special chars.
   Example: "Passcode Feature" → `passcode-feature`

2. **Slack channels** — comma-separated channel names (with or without `#`).
   For each, verify accessibility via `slack_search_channels`. If not found, show error and re-ask.

3. **Jira project key** (optional) — e.g. `PTECH-31204`. If provided, call `getJiraIssue` with a search to verify. Show count of open issues if found.

4. **Confluence links** (optional) — paste RFC/spec/wiki URLs one per line. For each, call `getConfluencePage` to verify access, then use `cipher_extract_and_operate_memory` to index the content.

5. **Figma links** (optional) — store as plain refs (no indexing in v1).

6. **GitHub repos** (optional) — `org/repo` format. Store as refs. If provided, ask:
   `Index codebase now? [y/n]` — if yes, invoke the xgh:ingest-index-repo skill in quick mode.

## Step 2 — Initial backfill

Read the last 200 messages from each Slack channel using `slack_read_channel`. For each message containing a Jira/Confluence/GitHub link, stash it to `~/.xgh/inbox/` and add the ref to the enrichment list.

Show progress:
```
Scanning #ptech-31204-engineering... found 12 Jira links, 3 Confluence pages, 2 PRs
Auto-enriching project config with discovered references.
```

## Step 3 — Write to ingest.yaml

Use python3 to safely read, update, and write `~/.xgh/ingest.yaml` (read → modify dict → yaml.dump):

```yaml
projects:
  passcode-feature:
    status: active
    slack:
      - "#ptech-31204-general"
      - "#ptech-31204-engineering"
    jira: PTECH-31204
    confluence:
      - /spaces/PTECH/pages/rfc-passcode-v2
    github:
      - acme-corp/acme-ios
    figma:
      - https://figma.com/design/abc123/passcode-screens
    rfcs: []
    index:
      last_full: null
      schedule: weekly
      watch_paths: []
    last_scan: null
```

## Step 4 — Confirm

```
✓ Project "passcode-feature" added to ~/.xgh/ingest.yaml
  Channels: #ptech-31204-general, #ptech-31204-engineering
  Initial backfill: 15 items queued in ~/.xgh/inbox/
  Next retriever run will include this project.

Run /xgh-doctor to verify the full pipeline is healthy.
```
