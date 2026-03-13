#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

assert_file_exists() {
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: missing file $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  if ! grep -qi "$2" "$1" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 still contains '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_output() {
  local output
  output=$(bash "$1")
  if python3 - "$output" <<'PY'
import json
import sys
json.loads(sys.argv[1])
PY
  then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 did not emit valid JSON"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local output
  output=$(bash "$1")
  if [[ "$output" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected output from $1 to contain '$2'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists "hooks/session-start.sh"
assert_file_exists "hooks/prompt-submit.sh"

assert_not_contains "hooks/session-start.sh" "placeholder"
assert_not_contains "hooks/prompt-submit.sh" "placeholder"
assert_not_contains "hooks/session-start.sh" "not yet implemented"

assert_json_output "hooks/session-start.sh"
assert_json_output "hooks/prompt-submit.sh"

assert_output_contains "hooks/prompt-submit.sh" "cipher_memory_search"
assert_output_contains "hooks/prompt-submit.sh" "cipher_extract_and_operate_memory"

echo ""
echo "Hooks test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
