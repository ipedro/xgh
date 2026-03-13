#!/usr/bin/env bash
# ct-scoring.sh — Importance, recency decay, and maturity promotion/demotion
# Sourced by context-tree.sh; can also be sourced directly for testing.

HALF_LIFE_DAYS=21
PROMOTE_VALIDATED=65
PROMOTE_CORE=85
DEMOTE_CORE_THRESHOLD=25
DEMOTE_VALIDATED_THRESHOLD=30

IMPORTANCE_SEARCH_HIT=3
IMPORTANCE_UPDATE=5
IMPORTANCE_MANUAL_CURATE=10

# calculate_recency_decay DAYS_SINCE_UPDATE
# Returns float 0.0-1.0. Formula: e^(-ln(2) * days / HALF_LIFE)
calculate_recency_decay() {
  local days="$1"
  python3 -c "
import math
days = ${days}
half_life = ${HALF_LIFE_DAYS}
decay = math.exp(-math.log(2) * days / half_life)
print(f'{decay:.4f}')
"
}

# apply_recency_decay FILE
# Reads updatedAt, calculates days elapsed, sets recency field.
apply_recency_decay() {
  local file="$1"
  local updated_at
  updated_at=$(read_frontmatter_field "$file" "updatedAt")
  if [ -z "$updated_at" ]; then return; fi

  local days_elapsed
  days_elapsed=$(python3 -c "
from datetime import datetime
import sys
try:
    updated = datetime.strptime('${updated_at}', '%Y-%m-%dT%H:%M:%SZ')
    now = datetime.utcnow()
    delta = (now - updated).total_seconds() / 86400
    print(int(max(0, delta)))
except:
    print(0)
")

  local new_recency
  new_recency=$(calculate_recency_decay "$days_elapsed")
  update_frontmatter_field "$file" "recency" "$new_recency"
}

# evaluate_maturity FILE
# Promotes or demotes maturity based on importance with hysteresis.
evaluate_maturity() {
  local file="$1"
  local importance maturity
  importance=$(read_frontmatter_field "$file" "importance")
  maturity=$(read_frontmatter_field "$file" "maturity")
  importance=${importance:-0}
  maturity=${maturity:-draft}

  local new_maturity="$maturity"

  case "$maturity" in
    draft)
      if [ "$importance" -ge "$PROMOTE_CORE" ]; then
        new_maturity="core"
      elif [ "$importance" -ge "$PROMOTE_VALIDATED" ]; then
        new_maturity="validated"
      fi
      ;;
    validated)
      if [ "$importance" -ge "$PROMOTE_CORE" ]; then
        new_maturity="core"
      elif [ "$importance" -lt "$DEMOTE_VALIDATED_THRESHOLD" ]; then
        new_maturity="draft"
      fi
      ;;
    core)
      if [ "$importance" -lt "$DEMOTE_CORE_THRESHOLD" ]; then
        new_maturity="validated"
      fi
      ;;
  esac

  if [ "$new_maturity" != "$maturity" ]; then
    update_frontmatter_field "$file" "maturity" "$new_maturity"
  fi
}

# bump_importance FILE AMOUNT
bump_importance() {
  local file="$1" amount="$2"
  local imp
  imp=$(read_frontmatter_field "$file" "importance")
  imp=${imp:-0}
  local new_imp=$((imp + amount))
  [ "$new_imp" -gt 100 ] && new_imp=100
  update_frontmatter_field "$file" "importance" "$new_imp"
}

# cmd_score [--all]
# Runs recency decay and maturity evaluation on all context tree files.
cmd_score() {
  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"

  find "$ct_dir" -name "*.md" \
    ! -name "_index.md" \
    ! -name "context.md" \
    ! -name "*.stub.md" \
    -type f | while read -r file; do
    apply_recency_decay "$file"
    evaluate_maturity "$file"
  done

  echo "Scoring complete."
}
