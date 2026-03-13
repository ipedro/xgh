#!/usr/bin/env bash
# xgh post-install configure script
# Called by MCS after tech pack installation to set up project-specific state.
set -euo pipefail

PROJECT_PATH="${MCS_PROJECT_PATH:-.}"
TEAM_NAME="${MCS_RESOLVED_TEAM_NAME:-my-team}"
CONTEXT_TREE_PATH="${MCS_RESOLVED_CONTEXT_TREE_PATH:-.xgh/context-tree}"

# Resolve context tree to absolute path within the project
CONTEXT_TREE_DIR="${PROJECT_PATH}/${CONTEXT_TREE_PATH}"

echo "xgh configure: setting up project at ${PROJECT_PATH}"
echo "  team:         ${TEAM_NAME}"
echo "  context tree: ${CONTEXT_TREE_DIR}"

# Create context tree directory
mkdir -p "${CONTEXT_TREE_DIR}"

# Initialize _manifest.json if it doesn't exist
MANIFEST="${CONTEXT_TREE_DIR}/_manifest.json"
if [ ! -f "${MANIFEST}" ]; then
  CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "${MANIFEST}" <<EOF
{
  "version": "1.0.0",
  "team": "${TEAM_NAME}",
  "created": "${CREATED_AT}",
  "domains": []
}
EOF
  echo "  created:      ${MANIFEST}"
else
  echo "  exists:       ${MANIFEST} (unchanged)"
fi

echo "xgh configure: done"
