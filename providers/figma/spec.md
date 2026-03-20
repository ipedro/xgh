# Figma Provider Spec

Figma delivers design file comments into the xgh inbox. Supports bash and MCP modes.

## Mode Selection

During `/xgh-track`, ask: "Do you have a Figma personal access token, or is Figma connected via MCP/OAuth?"

- **Token available** → bash mode
- **MCP/OAuth** → mcp mode

## File Key Extraction

Figma URLs embed the file key as the path segment after `/file/` or `/design/`:

```
https://www.figma.com/file/ABC123/My-Design   →  file_key: ABC123
https://www.figma.com/design/XYZ789/Prototype →  file_key: XYZ789
```

During `/xgh-track`, parse the provided Figma URL with this pattern and store in `provider.yaml`:

```yaml
sources:
  - id: ABC123
    name: "My Design"
```

---

## Bash Mode

### Auth

Store a Figma personal access token in `tokens.env`:

```bash
FIGMA_TOKEN=figd_xxxxxxxxxxxxxxxxxxxx
```

Header for all requests: `X-Figma-Token: $FIGMA_TOKEN`

### Connection Test

```bash
curl -s -H "X-Figma-Token: $FIGMA_TOKEN" "https://api.figma.com/v1/me" | jq .handle
```

### fetch.sh Generation

For each file key defined in `provider.yaml`, generate a `fetch.sh` that:

1. Fetches comments for the file:

```bash
curl -s -H "X-Figma-Token: $FIGMA_TOKEN" \
  "https://api.figma.com/v1/files/$FILE_KEY/comments"
```

2. Extracts fields: comment ID, author (`user.handle`), message, `created_at`, `resolved_at`

3. Filters:
   - Only comments where `created_at > cursor`
   - Only unresolved comments (`resolved_at == null`)

4. Urgency: **low** — design comments are rarely blocking

5. Cursor: ISO 8601 timestamp from the most recent `created_at` in the response

### provider.yaml Example

```yaml
provider: figma
auth:
  type: token
  env_var: FIGMA_TOKEN
sources:
  - id: ABC123
    name: "My Design"
fetch:
  endpoint: "https://api.figma.com/v1/files/{id}/comments"
  headers:
    X-Figma-Token: "$FIGMA_TOKEN"
  cursor_field: created_at
  filter:
    resolved_at: null
urgency: low
inbox: figma-comments
```

---

## MCP Mode

### Auth

Uses Figma MCP server OAuth. Set in `provider.yaml`:

```yaml
auth:
  type: mcp_oauth
  mcp_server: figma
```

### mcp Section

```yaml
mcp:
  tools:
    - name: mcp__figma__get_file_comments
      params_template:
        file_key: "${SOURCE_ID}"
  result_mapping:
    items: ".comments"
    timestamp: ".created_at"
    text: ".message"
    author: ".user.handle"
```

### Connection Test

Call `mcp__figma__get_file_comments` with a known file key. Success if the tool returns without error.

### provider.yaml Example

```yaml
provider: figma
auth:
  type: mcp_oauth
  mcp_server: figma
sources:
  - id: ABC123
    name: "My Design"
mcp:
  tools:
    - name: mcp__figma__get_file_comments
      params_template:
        file_key: "${SOURCE_ID}"
  result_mapping:
    items: ".comments"
    timestamp: ".created_at"
    text: ".message"
    author: ".user.handle"
urgency: low
inbox: figma-comments
```

---

## Inbox Item Shape

```json
{
  "id": "comment:ABC123:<comment_id>",
  "provider": "figma",
  "source_id": "ABC123",
  "author": "designerhandle",
  "text": "Can we adjust the padding here?",
  "created_at": "2024-01-15T10:30:00Z",
  "resolved_at": null,
  "urgency": "low",
  "url": "https://www.figma.com/file/ABC123?node-id=..."
}
```
