#!/usr/bin/env bash
# xgh UserPromptSubmit hook
# Injects the xgh decision table on every user prompt.
# This reminds the agent to query memory before coding and curate after.
# Output: JSON {"result": "...decision table..."}
set -euo pipefail

# ── Helper: escape string for JSON ────────────────────────
json_escape() {
  python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps(text), end='')
" 2>/dev/null || {
    sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
  }
}

# ── Decision Table ─────────────────────────────────────────
DECISION_TABLE='[xgh Decision Table]

Before writing or modifying code:
  -> cipher_memory_search for prior knowledge, conventions, related decisions
  -> Check context tree for team patterns

After writing or modifying code:
  -> cipher_extract_and_operate_memory to capture what you learned
  -> Sync new patterns to context tree via /xgh-curate

After making an architectural or design decision:
  -> Curate: decision + rationale + alternatives considered
  -> Use cipher_store_reasoning_memory for the reasoning chain

After fixing a bug:
  -> Curate: root cause + fix + trigger conditions
  -> Search memory first — this bug may have been seen before

When reviewing a PR or code:
  -> Query context tree for related past decisions
  -> Curate any new patterns discovered during review

When ending a session:
  -> Ensure all significant learnings are curated
  -> Run /xgh-status to verify memory health

IRON LAW: Every coding session MUST query memory before writing code AND curate learnings before ending.'

# ── Output JSON ────────────────────────────────────────────
echo "{\"result\": $(echo "$DECISION_TABLE" | json_escape)}"
exit 0
