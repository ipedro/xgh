# Slack Provider Spec

Instructions for generating the Slack provider during `/xgh-track`.

## Mode Selection

During `/xgh-track`, ask the user: "Do you have a Slack Bot Token, or is Slack connected via MCP/OAuth?"

- **Bot Token available** → set `mode: bash` in `provider.yaml`
- **MCP/OAuth only** → set `mode: mcp` in `provider.yaml`

Corporate users behind SSO often cannot create a standalone bot token; they use MCP/OAuth exclusively.

---

## Bash Mode (`mode: bash`)

### Auth

- Store `SLACK_BOT_TOKEN` in `tokens.env` (never commit this file).
- Required bot token scopes: `channels:history`, `channels:read`, `search:read`, `users:read`.

### tokens.env Setup Prompt

Tell the user:
1. Go to https://api.slack.com/apps and create a new app (from scratch).
2. Under **OAuth & Permissions**, add Bot Token Scopes: `channels:history`, `channels:read`, `search:read`, `users:read`.
3. Install the app to your workspace.
4. Copy the **Bot User OAuth Token** (starts with `xoxb-`).
5. Add to `tokens.env`: `SLACK_BOT_TOKEN=xoxb-your-token-here`

### Connection Test

```bash
curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  https://slack.com/api/auth.test | jq .ok
```

Expected output: `true`

### Channel ID Resolution

During `/xgh-track`, resolve `#channel-name` → channel ID via:

```bash
curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  "https://slack.com/api/conversations.list?limit=200" | jq '.channels[] | {id, name}'
```

Store channel IDs (not names) in `provider.yaml`. Names change; IDs are stable.

### provider.yaml Structure

```yaml
provider: slack
mode: bash
auth:
  type: token
  env_var: SLACK_BOT_TOKEN
sources:
  - id: C0123456789        # channel ID, resolved from #general
    name: general
    cursor: ""             # Slack message ts (Unix timestamp with microseconds)
  - id: C9876543210
    name: engineering
    cursor: ""
```

### fetch.sh Generation

Generate `providers/slack/fetch.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../tokens.env"
PROVIDER_YAML="$(dirname "$0")/provider.yaml"

# Read channels from provider.yaml
CHANNELS=$(yq '.sources[] | .id + ":" + .cursor' "$PROVIDER_YAML")

while IFS= read -r entry; do
  CHANNEL_ID="${entry%%:*}"
  CURSOR="${entry##*:}"

  PARAMS="channel=$CHANNEL_ID&limit=50"
  [ -n "$CURSOR" ] && PARAMS="$PARAMS&oldest=$CURSOR"

  RESPONSE=$(curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    "https://slack.com/api/conversations.history?$PARAMS")

  echo "$RESPONSE" | jq -c --arg channel "$CHANNEL_ID" \
    '.messages[] | {ts, text, user, type, channel: $channel}'

done <<< "$CHANNELS"
```

### Message Extraction (jq)

Extract from each API response:

```bash
jq '.messages[] | {ts, text, user, type}'
```

### Urgency Scoring

During fetch, flag messages containing:
- `@here`, `@channel` — broadcast mentions
- User mentions matching `profile.slack_id` from `ingest.yaml`
- Urgency keywords from `provider.yaml` `urgency_keywords` list

### Cursor

Slack uses message `ts` (Unix timestamp with microseconds, e.g. `1711234567.123456`) as the cursor.

- Advance cursor to the `ts` of the most recent message fetched.
- Store updated cursor back to `provider.yaml` after each fetch.
- Pass as `oldest` parameter to `conversations.history` to fetch only new messages.

---

## MCP Mode (`mode: mcp`)

### Auth

Uses the existing Slack MCP server OAuth. No `tokens.env` entry needed.

```yaml
auth:
  type: mcp_oauth
  mcp_server: slack
```

### No fetch.sh

In MCP mode, there is no `fetch.sh`. The provider is driven entirely by `provider.yaml` tool call definitions.

### provider.yaml Structure

```yaml
provider: slack
mode: mcp
auth:
  type: mcp_oauth
  mcp_server: slack
sources:
  - id: C0123456789
    name: general
    cursor: ""
  - id: C9876543210
    name: engineering
    cursor: ""
mcp:
  tools:
    - name: mcp__slack__conversations_history
      params_template:
        channel: "${SOURCE_ID}"
        limit: 50
        oldest: "${CURSOR}"
  result_mapping:
    items: ".messages"
    timestamp: ".ts"
    text: ".text"
    author: ".user"
```

### Channel ID Resolution

Same as bash mode — resolve `#channel-name` → channel ID during `/xgh-track` using the MCP tool `mcp__slack__conversations_list` or equivalent.

### Connection Test

Call the MCP tool with `limit: 1` and verify the response contains `.ok: true` or a non-empty `.messages` array.

---

## Inbox Output Format

Both modes produce inbox items in the standard format:

```json
{
  "source": "slack",
  "channel": "C0123456789",
  "ts": "1711234567.123456",
  "text": "message text",
  "user": "U0123456789",
  "urgency": "high"
}
```

Items are written to `.xgh/inbox/slack-<timestamp>.json` for processing by `/xgh-analyze`.
