#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/ct-frontmatter.sh"
source "${SCRIPT_DIR}/scripts/ct-scoring.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $label — expected '$expected', got '$actual'"
  fi
}

# --- Named constants exist ---
assert_eq "HALF_LIFE_DAYS" "21" "$HALF_LIFE_DAYS"
assert_eq "PROMOTE_VALIDATED" "65" "$PROMOTE_VALIDATED"
assert_eq "PROMOTE_CORE" "85" "$PROMOTE_CORE"
assert_eq "DEMOTE_CORE_THRESHOLD" "25" "$DEMOTE_CORE_THRESHOLD"
assert_eq "DEMOTE_VALIDATED_THRESHOLD" "30" "$DEMOTE_VALIDATED_THRESHOLD"
assert_eq "IMPORTANCE_SEARCH_HIT" "3" "$IMPORTANCE_SEARCH_HIT"
assert_eq "IMPORTANCE_UPDATE" "5" "$IMPORTANCE_UPDATE"
assert_eq "IMPORTANCE_MANUAL_CURATE" "10" "$IMPORTANCE_MANUAL_CURATE"

# --- ct_score_recency ---
# 0 days ago → recency 1.0
RECENCY=$(ct_score_recency "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
assert_eq "recency today" "1.0000" "$RECENCY"

# 21 days ago → recency ~0.5 (half-life)
PAST_DATE=$(python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(days=21)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
RECENCY_21=$(ct_score_recency "$PAST_DATE")
# Accept 0.4900-0.5100 range (half-life approximation)
python3 -c "assert 0.49 <= float('$RECENCY_21') <= 0.51, f'Expected ~0.5, got $RECENCY_21'" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: recency at half-life — got $RECENCY_21"; }

# --- ct_score_maturity (hysteresis) ---
# draft → validated at 65
assert_eq "draft→validated at 65" "validated" "$(ct_score_maturity 65 draft)"
# draft stays draft at 64
assert_eq "draft stays at 64" "draft" "$(ct_score_maturity 64 draft)"
# validated → core at 85
assert_eq "validated→core at 85" "core" "$(ct_score_maturity 85 validated)"
# core stays core at 26 (hysteresis: demotion threshold is 25)
assert_eq "core stays at 26" "core" "$(ct_score_maturity 26 core)"
# core → validated at 24
assert_eq "core→validated at 24" "validated" "$(ct_score_maturity 24 core)"
# validated stays at 31 (hysteresis: demotion threshold is 30)
assert_eq "validated stays at 31" "validated" "$(ct_score_maturity 31 validated)"
# validated → draft at 29
assert_eq "validated→draft at 29" "draft" "$(ct_score_maturity 29 validated)"

# --- ct_score_apply_event ---
cat > "$TMP/entry.md" <<'EOF'
---
title: Test Entry
importance: 50
recency: 1.0000
maturity: draft
accessCount: 0
updateCount: 0
createdAt: 2026-03-13T00:00:00Z
updatedAt: 2026-03-13T00:00:00Z
---
Body
EOF

ct_score_apply_event "$TMP/entry.md" "search-hit"
assert_eq "importance after search-hit" "53" "$(ct_frontmatter_get "$TMP/entry.md" "importance")"

ct_score_apply_event "$TMP/entry.md" "update"
assert_eq "importance after update" "58" "$(ct_frontmatter_get "$TMP/entry.md" "importance")"

ct_score_apply_event "$TMP/entry.md" "manual"
assert_eq "importance after manual" "68" "$(ct_frontmatter_get "$TMP/entry.md" "importance")"

# maturity should have promoted to validated (68 >= 65)
assert_eq "maturity promoted" "validated" "$(ct_frontmatter_get "$TMP/entry.md" "maturity")"

# --- importance capped at 100 ---
ct_frontmatter_set "$TMP/entry.md" "importance" "98"
ct_score_apply_event "$TMP/entry.md" "manual"
assert_eq "importance capped" "100" "$(ct_frontmatter_get "$TMP/entry.md" "importance")"

# --- exact boundary: core stays at 25 (threshold is < 25, not <= 25) ---
assert_eq "core stays at exactly 25" "core" "$(ct_score_maturity 25 core)"

# --- ct_score_recalculate ---
cat > "$TMP/recalc.md" <<'EOF'
---
title: Recalculate Test
importance: 70
recency: 0.5000
maturity: draft
createdAt: 2026-03-13T00:00:00Z
updatedAt: 2026-03-13T00:00:00Z
---
Body
EOF

ct_score_recalculate "$TMP/recalc.md"
# importance 70 >= 65, so maturity should promote to validated
assert_eq "recalculate promotes maturity" "validated" "$(ct_frontmatter_get "$TMP/recalc.md" "maturity")"
# recency should be recalculated from updatedAt (not left at 0.5)
RECALC_RECENCY=$(ct_frontmatter_get "$TMP/recalc.md" "recency")
[ "$RECALC_RECENCY" != "0.5000" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: recalculate should update recency"; }

echo "Scoring tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
