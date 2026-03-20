#!/usr/bin/env bash
set -euo pipefail

# detect-project.sh — Resolve cwd to a tracked project in ingest.yaml
#
# Logic:
#   1. Get git remote origin URL from cwd's repo
#   2. Extract owner/repo from the URL
#   3. Match against all projects' github: lists in ingest.yaml
#   4. If matched, resolve dependencies
#   5. Output: XGH_PROJECT=<name> and XGH_PROJECT_SCOPE=<name,dep1,dep2>
#
# If cwd is not in a git repo, or the repo doesn't match any project,
# both values are empty (= all-projects mode).

INGEST="${XGH_INGEST:-$HOME/.xgh/ingest.yaml}"

# Step 1: Get git remote origin URL
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "XGH_PROJECT="; echo "XGH_PROJECT_SCOPE="; exit 0; }
REMOTE_URL=$(git -C "$GIT_ROOT" remote get-url origin 2>/dev/null) || { echo "XGH_PROJECT="; echo "XGH_PROJECT_SCOPE="; exit 0; }

# Step 2: Extract owner/repo from URL
# Handles: git@github.com:owner/repo.git, https://github.com/owner/repo.git, https://github.com/owner/repo
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##')

if [ -z "$OWNER_REPO" ] || [ ! -f "$INGEST" ]; then
    echo "XGH_PROJECT="
    echo "XGH_PROJECT_SCOPE="
    exit 0
fi

# Step 3: Match against ingest.yaml projects
# Use python for safe YAML parsing
RESULT=$(python3 -c "
import yaml, sys

with open('$INGEST') as f:
    config = yaml.safe_load(f)

projects = config.get('projects', {})
target = '$OWNER_REPO'
matched = None

for name, proj in projects.items():
    if not isinstance(proj, dict):
        continue
    repos = proj.get('github', []) or []
    if isinstance(repos, str):
        repos = [repos]
    for repo in repos:
        if repo.lower() == target.lower():
            matched = name
            break
    if matched:
        break

if not matched:
    print('')
    print('')
    sys.exit(0)

# Step 4: Resolve dependencies
deps = projects[matched].get('dependencies', []) or []
scope = [matched] + [d for d in deps if d in projects]

print(matched)
print(','.join(scope))
" 2>/dev/null) || { echo "XGH_PROJECT="; echo "XGH_PROJECT_SCOPE="; exit 0; }

PROJECT=$(echo "$RESULT" | head -1)
SCOPE=$(echo "$RESULT" | tail -1)

echo "XGH_PROJECT=$PROJECT"
echo "XGH_PROJECT_SCOPE=$SCOPE"
