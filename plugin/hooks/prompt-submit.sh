#!/usr/bin/env bash
# xgh UserPromptSubmit hook
# Lightweight — static memory instructions moved to xgh-instructions.md (@reference).
# This hook only handles dynamic context-mode health nudges.
set -euo pipefail

python3 << 'PYEOF'
import json, os

# Session health nudge — context-mode enforcement
nudge = ""
state_override = os.environ.get("XGH_CTX_STATE_OVERRIDE", "")
if state_override:
    ctx_state_path = state_override
else:
    import hashlib, subprocess as sp
    try:
        proj = sp.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=sp.DEVNULL
        ).decode().strip()
    except Exception:
        proj = os.getcwd()
    h = hashlib.sha1(proj.encode()).hexdigest()[:8]
    ctx_state_path = f"/tmp/xgh-ctx-health-{h}.json"

try:
    with open(ctx_state_path) as f:
        ctx_state = json.load(f)
    unedited = ctx_state.get("reads", 0) - ctx_state.get("edits", 0)
    ctx_calls = ctx_state.get("ctx_calls", 0)
    if ctx_calls < 2 and unedited >= 3:
        nudge = (
            f"Session health: {ctx_state['reads']} reads, "
            f"{ctx_state['edits']} edits, {ctx_calls} context-mode calls. "
            f"Switch to ctx_execute_file for analysis reads."
        )
except (FileNotFoundError, json.JSONDecodeError, KeyError):
    pass

if nudge:
    print(json.dumps({"additionalContext": nudge}))
else:
    print(json.dumps({}))
PYEOF
exit 0
