# MCP Auto-Detection Protocol

## Detection Protocol

Before starting any skill, auto-detect which MCP servers are available. Skills adapt based on what is configured — no hard dependencies.

**How to detect:**
- For MCP integrations: Check whether the tool functions are available in the current tool list.
- For CLI integrations (GitHub): Check CLI availability via `command -v` or by running a help command.
Available integrations are discovered automatically on first invocation. Call `xgh:mcp-setup` for any missing MCP the user wants to configure.

## Common Tool Signatures by Integration

| Integration | Detection signal | Capability |
|-------------|-----------------|------------|
| lossless-claude | `mcp__lossless-claude__lcm_search` tool available | xgh memory, session state, conventions |
| Slack MCP | `mcp__claude_ai_Slack__slack_read_thread` tool available | Thread reading, message search |
| Atlassian/Jira | `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` tool available | Ticket history, task management |
| GitHub | `gh pr list` / `gh issue list` available (CLI detection; no standard MCP server for GitHub) | PRs, issues, Actions |
| Figma MCP | `mcp__claude_ai_Figma__get_design_context` tool available | Design extraction, Code Connect |
| Gmail | `gmail_search_messages` tool available | Email search and reading |

## Status Reporting Format

After detection, surface which integrations are available so the user understands what is active:

```
✓ lossless-claude — memory and conventions available
✓ Slack — thread reading and search available
✓ Atlassian — Jira ticket access available
✗ Figma — not configured (will ask for manual input if needed)
```

## Graceful Degradation Principle

Skills should always work, even with zero MCPs. When a tool is unavailable:
1. Skip the step that depends on it
2. Fall back to asking the user for the missing information directly
3. Note any limitations in the output (e.g., "no ticket created — task manager not configured")

## Skill-Specific Degradation Rules

Each skill defines its own degradation rules inline — what specifically to skip or substitute when each integration is absent. These rules are skill-specific and live in each skill's `## MCP Auto-Detection` section after a reference to this protocol.
