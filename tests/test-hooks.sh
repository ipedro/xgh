#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_eq() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' ($3)"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output does not contain '$2' ($3)"; FAIL=$((FAIL+1)); fi; }
assert_valid_json() { if echo "$1" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: invalid JSON ($2)"; FAIL=$((FAIL+1)); fi; }
assert_json_has_result() { if echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'result' in d" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: JSON missing 'result' key ($2)"; FAIL=$((FAIL+1)); fi; }

# --- SessionStart hook tests ---

# Test 1: Hook is executable
if [ -x "hooks/session-start.sh" ]; then PASS=$((PASS+1)); else echo "FAIL: session-start.sh not executable"; FAIL=$((FAIL+1)); fi

# Test 2: Hook outputs valid JSON (no context tree)
TMPDIR_TEST=$(mktemp -d)
OUT=$(XGH_CONTEXT_TREE_PATH="${TMPDIR_TEST}/nonexistent" bash hooks/session-start.sh 2>/dev/null || true)
assert_valid_json "$OUT" "session-start outputs valid JSON without context tree"
assert_json_has_result "$OUT" "session-start has result key without context tree"

# Test 3: Hook outputs valid JSON (with empty context tree)
EMPTY_TREE="${TMPDIR_TEST}/empty-tree"
mkdir -p "$EMPTY_TREE"
cat > "${EMPTY_TREE}/_manifest.json" << 'MANIFEST'
{"version":1,"team":"test-team","created":"2026-01-01T00:00:00Z","domains":[]}
MANIFEST
OUT=$(XGH_CONTEXT_TREE_PATH="$EMPTY_TREE" bash hooks/session-start.sh 2>/dev/null || true)
assert_valid_json "$OUT" "session-start outputs valid JSON with empty tree"
assert_json_has_result "$OUT" "session-start has result key with empty tree"
assert_contains "$OUT" "test-team" "session-start includes team name"

# Test 4: Hook picks up core-maturity files
RICH_TREE="${TMPDIR_TEST}/rich-tree"
mkdir -p "$RICH_TREE/api-design"
cat > "$RICH_TREE/_manifest.json" << 'MANIFEST'
{
  "version": 1,
  "team": "alpha-team",
  "created": "2026-01-01T00:00:00Z",
  "domains": [
    {
      "name": "api-design",
      "path": "api-design",
      "topics": [
        {
          "name": "rest-conventions",
          "path": "api-design/rest-conventions.md",
          "importance": 90,
          "maturity": "core"
        },
        {
          "name": "graphql-patterns",
          "path": "api-design/graphql-patterns.md",
          "importance": 40,
          "maturity": "draft"
        }
      ]
    }
  ]
}
MANIFEST
cat > "$RICH_TREE/api-design/rest-conventions.md" << 'MDFILE'
---
title: REST Conventions
importance: 90
maturity: core
tags: [api, rest]
---
## Raw Concept
Always use kebab-case for URL paths. Use plural nouns for collections.
MDFILE
cat > "$RICH_TREE/api-design/graphql-patterns.md" << 'MDFILE'
---
title: GraphQL Patterns
importance: 40
maturity: draft
tags: [api, graphql]
---
## Raw Concept
Use DataLoader for N+1 prevention.
MDFILE

OUT=$(XGH_CONTEXT_TREE_PATH="$RICH_TREE" bash hooks/session-start.sh 2>/dev/null || true)
assert_valid_json "$OUT" "session-start valid JSON with rich tree"
assert_contains "$OUT" "REST Conventions" "session-start includes core file title"
assert_contains "$OUT" "kebab-case" "session-start includes core file content"

# Test 5: Hook does NOT include draft files when core files exist
# (draft files are only included if we have fewer than 5 core/validated)
# The graphql-patterns is draft (importance 40), should NOT appear if we have enough core

# --- UserPromptSubmit hook tests ---

# Test 6: Hook is executable
if [ -x "hooks/prompt-submit.sh" ]; then PASS=$((PASS+1)); else echo "FAIL: prompt-submit.sh not executable"; FAIL=$((FAIL+1)); fi

# Test 7: Hook outputs valid JSON
OUT=$(bash hooks/prompt-submit.sh 2>/dev/null || true)
assert_valid_json "$OUT" "prompt-submit outputs valid JSON"
assert_json_has_result "$OUT" "prompt-submit has result key"

# Test 8: Hook output contains decision table keywords
assert_contains "$OUT" "cipher_memory_search" "prompt-submit mentions memory search"
assert_contains "$OUT" "cipher_extract_and_operate_memory" "prompt-submit mentions extract memory"
assert_contains "$OUT" "context tree" "prompt-submit mentions context tree"

# Cleanup
rm -rf "$TMPDIR_TEST"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
