#!/usr/bin/env bash
# xgh PostToolUse hook — ctx_execute / ctx_execute_file / ctx_batch_execute / ctx_search / ctx_fetch_and_index
# Increments ctx_calls counter to track context-mode usage.
set -euo pipefail

# Consume stdin
cat > /dev/null 2>&1 || true

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

# Update state
state["ctx_calls"] += 1

# Write state
with open(state_path, "w") as f:
    json.dump(state, f)
PYEOF
