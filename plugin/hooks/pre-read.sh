#!/usr/bin/env bash
# xgh PreToolUse hook — Read
# Escalating advisory based on unedited-read count.
# Output: {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "..."}}
set -euo pipefail

# Capture any stdin (Claude Code may pass tool input JSON)
export XGH_HOOK_INPUT=$(cat 2>/dev/null || echo '{}')

python3 << 'PYEOF'
import json, os, hashlib, subprocess

# Determine state file path
override = os.environ.get("XGH_CTX_STATE_OVERRIDE", "")
if override:
    state_path = override
else:
    try:
        project_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        project_root = os.getcwd()
    hash_val = hashlib.sha1(project_root.encode()).hexdigest()[:8]
    state_path = f"/tmp/xgh-ctx-health-{hash_val}.json"

# Read or initialize state
try:
    with open(state_path) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {"reads": 0, "edits": 0, "ctx_calls": 0, "files_read": []}

# Try to extract file path from hook input
try:
    hook_input = json.loads(os.environ.get("XGH_HOOK_INPUT", "{}"))
    file_path = hook_input.get("tool_input", {}).get("file_path", "")
except (json.JSONDecodeError, TypeError, AttributeError):
    file_path = ""

# Update state
state["reads"] += 1
if file_path and file_path not in state["files_read"]:
    state["files_read"].append(file_path)

# Write state
with open(state_path, "w") as f:
    json.dump(state, f)

# Compute escalation
unedited = state["reads"] - state["edits"]
ctx = state["ctx_calls"]

# Suppress warnings if agent has demonstrated context-mode awareness
if ctx >= 2:
    msg = "Context-mode: use ctx_execute_file for analysis reads."
elif unedited >= 5:
    files_str = ", ".join(os.path.basename(f) for f in state["files_read"][-5:]) if state["files_read"] else ""
    parts = [
        f"\U0001f6d1 {state['reads']} reads, {state['edits']} edits, {ctx} ctx calls.",
        "You are wasting context. Switch to ctx_execute_file NOW.",
    ]
    if files_str:
        parts.append(f"Unedited: {files_str}.")
    parts.append("See plugin/references/context-mode-routing.md")
    msg = " ".join(parts)
elif unedited >= 3:
    files_str = ", ".join(os.path.basename(f) for f in state["files_read"][-3:]) if state["files_read"] else ""
    parts = [
        f"\u26a0\ufe0f You have read {state['reads']} files and edited {state['edits']}.",
        "Use ctx_execute_file for analysis.",
    ]
    if files_str:
        parts.append(f"Unedited: {files_str}")
    msg = " ".join(parts)
else:
    msg = "Context-mode: use ctx_execute_file for analysis reads."

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": msg
    }
}
print(json.dumps(output))
PYEOF
