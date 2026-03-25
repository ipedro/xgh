#!/usr/bin/env bash
# hooks/session-start-preferences.sh — SessionStart preference injection
# Epic 0.1: Builds a compact preference index from config/project.yaml
# and injects it as additionalContext at session start.
#
# Coexistence contract: LAST in the SessionStart hook array.
# Output: JSON with `additionalContext` key containing the preference index.
set -euo pipefail

# Locate project root (walk up from cwd)
_find_project_root() {
  local dir
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -f "${dir}/config/project.yaml" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT=""
if ! PROJECT_ROOT=$(_find_project_root 2>/dev/null); then
  # No project.yaml found — skip injection silently
  exit 0
fi

PROJ_YAML="${PROJECT_ROOT}/config/project.yaml"

python3 - "$PROJ_YAML" "$PROJECT_ROOT" << 'PYEOF'
import sys, os, json, subprocess

proj_yaml = sys.argv[1]
project_root = sys.argv[2]

# --- YAML reader (yq primary, Python fallback) ---
def read_yaml_field(yaml_path, yq_expr):
    """Read a field using yq, falling back to Python yaml.safe_load."""
    try:
        result = subprocess.run(
            ["yq", yq_expr, yaml_path],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            val = result.stdout.strip()
            if val and val not in ("null", "~", ""):
                return val
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    # Python fallback
    try:
        import yaml
        with open(yaml_path) as f:
            data = yaml.safe_load(f) or {}
        # Navigate the expression: convert '.preferences.pr.repo' to key chain
        keys = [k for k in yq_expr.strip(".").split(".") if k]
        val = data
        for k in keys:
            if isinstance(val, dict):
                val = val.get(k)
            else:
                val = None
            if val is None:
                return ""
        return str(val) if val is not None else ""
    except Exception:
        return ""

def load_yaml_full(yaml_path):
    """Load full YAML as dict using yq (JSON output) or Python fallback."""
    try:
        result = subprocess.run(
            ["yq", "-o=json", ".", yaml_path],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    try:
        import yaml
        with open(yaml_path) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return None

# --- Load YAML ---
if not os.path.isfile(proj_yaml):
    sys.exit(0)

data = load_yaml_full(proj_yaml)
if data is None:
    # Malformed YAML — warn once and skip
    warning = (
        "[xgh] WARNING: config/project.yaml has syntax errors — "
        "preferences disabled this session. "
        "Run 'yq . config/project.yaml' to diagnose."
    )
    print(json.dumps({"additionalContext": warning}))
    sys.exit(0)

prefs = data.get("preferences", {})

# --- Current branch ---
branch = ""
try:
    r = subprocess.run(
        ["git", "-C", project_root, "branch", "--show-current"],
        capture_output=True, text=True, timeout=5
    )
    if r.returncode == 0:
        branch = r.stdout.strip()
except Exception:
    pass

# --- Build domain lines (only domains with values) ---
lines = []

# PR domain — use load_pr_pref cascade (branch override > default > probe)
pr = prefs.get("pr", {})
branches = pr.get("branches", {})
branch_pr = branches.get(branch, {}) if branch else {}
if pr:
    fields = {}
    for field in ["repo", "provider", "reviewer", "merge_method"]:
        val = branch_pr.get(field) or pr.get(field) or ""
        if val:
            fields[field] = str(val)
    if fields:
        parts = " ".join(f"{k}={v}" for k, v in fields.items())
        lines.append(f"pr: {parts}")

# Dispatch domain
dispatch = prefs.get("dispatch", {})
if dispatch:
    fields = {}
    for field in ["default_agent", "exec_effort"]:
        val = dispatch.get(field, "")
        if val:
            fields[field] = str(val)
    if fields:
        parts = " ".join(f"{k}={v}" for k, v in fields.items())
        lines.append(f"dispatch: {parts}")

# Superpowers domain
superpowers = prefs.get("superpowers", {})
if superpowers:
    fields = {}
    for field in ["implementation_model", "review_model", "effort"]:
        val = superpowers.get(field, "")
        if val:
            fields[field] = str(val)
    if fields:
        parts = " ".join(f"{k}={v}" for k, v in fields.items())
        lines.append(f"superpowers: {parts}")

# VCS domain
vcs = prefs.get("vcs", {})
if vcs:
    fields = {}
    for field in ["commit_format", "branch_naming"]:
        val = vcs.get(field, "")
        if val:
            fields[field] = str(val)
    if fields:
        parts = " ".join(f"{k}={v}" for k, v in fields.items())
        lines.append(f"vcs: {parts}")

# Agents domain
agents = prefs.get("agents", {})
if agents:
    val = agents.get("default_model", "")
    if val:
        lines.append(f"agents: default_model={val}")

# Skip injection if no domains have values
if not lines:
    sys.exit(0)

# --- Count pending preferences ---
import glob as _glob
pending_files = _glob.glob(os.path.join(project_root, ".xgh", "pending-preferences-*.yaml"))
pending_count = len(pending_files)

# --- Assemble output ---
header = f"[xgh preferences] branch={branch}" if branch else "[xgh preferences]"
body = "\n".join(lines)
footer = f"Pending preferences: {pending_count}"
additional_context = f"{header}\n{body}\n{footer}"

print(json.dumps({"additionalContext": additional_context}))
PYEOF
