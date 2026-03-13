#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts"
source "${SCRIPT_DIR}/ct-frontmatter.sh"
source "${SCRIPT_DIR}/ct-scoring.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "${CT_DIR}/test-domain/test-topic"
export XGH_CONTEXT_TREE_DIR="$CT_DIR"

create_test_file() {
  local file="$1" importance="$2" recency="$3" maturity="$4" updated_at="${5:-2026-03-13T00:00:00Z}"
  cat > "$file" <<EOF
---
title: Test File
tags: [test]
keywords: [test]
importance: ${importance}
recency: ${recency}
maturity: ${maturity}
accessCount: 5
updateCount: 2
createdAt: 2026-01-01T00:00:00Z
updatedAt: ${updated_at}
source: manual
fromAgent: test
---

Test content.
EOF
}

# --- Test: recency decay calculation ---
DECAY_21=$(calculate_recency_decay 21)
echo "21-day decay: $DECAY_21"
DECAY_INT=$(echo "$DECAY_21" | awk '{printf "%d", $1 * 100}')
if [ "$DECAY_INT" -ge 49 ] && [ "$DECAY_INT" -le 51 ]; then
  PASS=$((PASS+1))
else
  echo "FAIL: 21-day decay should be ~0.50, got $DECAY_21"
  FAIL=$((FAIL+1))
fi

DECAY_0=$(calculate_recency_decay 0)
DECAY_0_INT=$(echo "$DECAY_0" | awk '{printf "%d", $1 * 100}')
assert_eq "$DECAY_0_INT" "100" "0-day decay is 1.0"

DECAY_42=$(calculate_recency_decay 42)
DECAY_42_INT=$(echo "$DECAY_42" | awk '{printf "%d", $1 * 100}')
if [ "$DECAY_42_INT" -ge 24 ] && [ "$DECAY_42_INT" -le 26 ]; then
  PASS=$((PASS+1))
else
  echo "FAIL: 42-day decay should be ~0.25, got $DECAY_42"
  FAIL=$((FAIL+1))
fi

# --- Test: maturity promotion draft -> validated at importance >= 65 ---
FILE1="${CT_DIR}/test-domain/test-topic/promote-test.md"
create_test_file "$FILE1" "65" "0.9" "draft"
evaluate_maturity "$FILE1"
MAT=$(read_frontmatter_field "$FILE1" "maturity")
assert_eq "$MAT" "validated" "draft promoted to validated at importance 65"

# --- Test: maturity promotion validated -> core at importance >= 85 ---
FILE2="${CT_DIR}/test-domain/test-topic/core-test.md"
create_test_file "$FILE2" "85" "0.9" "validated"
evaluate_maturity "$FILE2"
MAT2=$(read_frontmatter_field "$FILE2" "maturity")
assert_eq "$MAT2" "core" "validated promoted to core at importance 85"

# --- Test: hysteresis — core does NOT demote until importance < 25 (85 - 60) ---
FILE3="${CT_DIR}/test-domain/test-topic/hysteresis-core.md"
create_test_file "$FILE3" "30" "0.5" "core"
evaluate_maturity "$FILE3"
MAT3=$(read_frontmatter_field "$FILE3" "maturity")
assert_eq "$MAT3" "core" "core stays core at importance 30 (above 25 threshold)"

FILE4="${CT_DIR}/test-domain/test-topic/hysteresis-core-demote.md"
create_test_file "$FILE4" "24" "0.3" "core"
evaluate_maturity "$FILE4"
MAT4=$(read_frontmatter_field "$FILE4" "maturity")
assert_eq "$MAT4" "validated" "core demotes to validated at importance 24"

# --- Test: hysteresis — validated does NOT demote until importance < 30 (65 - 35) ---
FILE5="${CT_DIR}/test-domain/test-topic/hysteresis-val.md"
create_test_file "$FILE5" "35" "0.5" "validated"
evaluate_maturity "$FILE5"
MAT5=$(read_frontmatter_field "$FILE5" "maturity")
assert_eq "$MAT5" "validated" "validated stays at importance 35 (above 30 threshold)"

FILE6="${CT_DIR}/test-domain/test-topic/hysteresis-val-demote.md"
create_test_file "$FILE6" "29" "0.3" "validated"
evaluate_maturity "$FILE6"
MAT6=$(read_frontmatter_field "$FILE6" "maturity")
assert_eq "$MAT6" "draft" "validated demotes to draft at importance 29"

# --- Test: apply_recency_decay updates recency field based on updatedAt ---
FILE7="${CT_DIR}/test-domain/test-topic/decay-test.md"
TWENTY_ONE_DAYS_AGO=$(python3 -c "
from datetime import datetime, timedelta
d = datetime.utcnow() - timedelta(days=21)
print(d.strftime('%Y-%m-%dT%H:%M:%SZ'))
")
create_test_file "$FILE7" "50" "1.0" "draft" "$TWENTY_ONE_DAYS_AGO"
apply_recency_decay "$FILE7"
NEW_RECENCY=$(read_frontmatter_field "$FILE7" "recency")
REC_INT=$(echo "$NEW_RECENCY" | awk '{printf "%d", $1 * 100}')
if [ "$REC_INT" -ge 48 ] && [ "$REC_INT" -le 52 ]; then
  PASS=$((PASS+1))
else
  echo "FAIL: recency after 21 days should be ~0.50, got $NEW_RECENCY"
  FAIL=$((FAIL+1))
fi

# --- Test: cmd_score runs scoring on all files ---
cmd_score --all
assert_file_contains "$FILE1" "maturity:" "scoring preserved maturity field"

echo ""
echo "Scoring tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
