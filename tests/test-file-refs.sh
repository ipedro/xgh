#!/usr/bin/env bash
set -euo pipefail

# ── File Reference Integrity ─────────────────────────────
# Validates that files referenced in techpack.yaml actually exist.
# Checks: source:, contentFile:, settingsFile:, and script: fields.
# ─────────────────────────────────────────────────────────

PASS=0; FAIL=0

assert_file_exists() {
  if [ -f "$1" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: referenced file missing: $1"
    FAIL=$((FAIL + 1))
  fi
}

# Extract file references from techpack.yaml
for field in source contentFile settingsFile; do
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    assert_file_exists "$ref"
  done < <(grep "${field}:" techpack.yaml 2>/dev/null | sed "s/.*${field}: *//" | tr -d '"' | tr -d "'")
done

# configureProject.script
script=$(grep -A1 'configureProject:' techpack.yaml 2>/dev/null | grep 'script:' | sed 's/.*script: *//' | tr -d '"' | tr -d "'")
if [ -n "$script" ]; then
  assert_file_exists "$script"
fi

echo ""; echo "File reference test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
