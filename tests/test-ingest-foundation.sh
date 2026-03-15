#!/usr/bin/env bash
# tests/test-ingest-foundation.sh
set -euo pipefail
PASS=0; FAIL=0
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 does not contain '$2'"; FAIL=$((FAIL+1)); fi; }

assert_file_exists "lib/workspace-write.js"
assert_contains "lib/workspace-write.js" "xgh_schema_version"
assert_contains "lib/workspace-write.js" "cipher.yml"
assert_contains "lib/workspace-write.js" "dry-run"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
