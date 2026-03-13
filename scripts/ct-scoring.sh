#!/usr/bin/env bash
# ct-scoring.sh — Importance, recency decay, and maturity promotion/demotion
# Sourceable library: defines ct_score_recency, ct_score_maturity,
# ct_score_recalculate, ct_score_apply_event.

_CT_SCORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ct-frontmatter.sh
source "${_CT_SCORING_DIR}/ct-frontmatter.sh"

# --- Named constants ---
HALF_LIFE_DAYS=21
PROMOTE_VALIDATED=65
PROMOTE_CORE=85
DEMOTE_CORE_THRESHOLD=25
DEMOTE_VALIDATED_THRESHOLD=30

IMPORTANCE_SEARCH_HIT=3
IMPORTANCE_UPDATE=5
IMPORTANCE_MANUAL_CURATE=10

# _ct_frontmatter_set_raw FILE KEY VALUE
# Sets a frontmatter field without updating updatedAt.
_ct_frontmatter_set_raw() {
  local file=${1:?file required}
  local key=${2:?key required}
  local value=${3:?value required}
  local tmp
  tmp=$(mktemp)

  awk -v key="$key" -v value="$value" '
    BEGIN { in_fm = 0; replaced = 0 }

    NR == 1 && $0 == "---" {
      in_fm = 1
      print
      next
    }

    in_fm && $0 == "---" {
      if (replaced == 0) {
        print key ": " value
      }
      in_fm = 0
      print
      next
    }

    in_fm {
      if ($0 ~ "^[[:space:]]*" key ":[[:space:]]*") {
        print key ": " value
        replaced = 1
        next
      }
    }

    { print }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}

# ct_score_recency UPDATED_AT
# Returns recency as a float (4 decimal places) based on exponential decay.
# Formula: e^(-ln(2) * days / HALF_LIFE_DAYS)
ct_score_recency() {
  local updated_at=${1:?updated_at required}
  python3 -c "
from datetime import datetime
import math
updated = datetime.strptime('${updated_at}', '%Y-%m-%dT%H:%M:%SZ')
now = datetime.utcnow()
days = max(0.0, (now - updated).total_seconds() / 86400.0)
decay = math.exp(-math.log(2) * days / ${HALF_LIFE_DAYS})
print(f'{decay:.4f}')
"
}

# ct_score_maturity IMPORTANCE CURRENT_MATURITY
# Returns new maturity level with hysteresis thresholds.
ct_score_maturity() {
  local importance=${1:?importance required}
  local current=${2:?current_maturity required}

  case "$current" in
    draft)
      if [ "$importance" -ge "$PROMOTE_CORE" ]; then
        echo "core"
      elif [ "$importance" -ge "$PROMOTE_VALIDATED" ]; then
        echo "validated"
      else
        echo "draft"
      fi
      ;;
    validated)
      if [ "$importance" -ge "$PROMOTE_CORE" ]; then
        echo "core"
      elif [ "$importance" -lt "$DEMOTE_VALIDATED_THRESHOLD" ]; then
        echo "draft"
      else
        echo "validated"
      fi
      ;;
    core)
      if [ "$importance" -lt "$DEMOTE_CORE_THRESHOLD" ]; then
        echo "validated"
      else
        echo "core"
      fi
      ;;
    *)
      echo "$current"
      ;;
  esac
}

# ct_score_apply_event FILE EVENT
# Bumps importance by event amount, caps at 100, updates maturity.
# Does NOT touch updatedAt or recency.
ct_score_apply_event() {
  local file=${1:?file required}
  local event=${2:?event required}
  local amount

  case "$event" in
    search-hit) amount=$IMPORTANCE_SEARCH_HIT ;;
    update)     amount=$IMPORTANCE_UPDATE ;;
    manual)     amount=$IMPORTANCE_MANUAL_CURATE ;;
    *)          echo "Unknown event: $event" >&2; return 1 ;;
  esac

  local importance
  importance=$(ct_frontmatter_get "$file" "importance" 2>/dev/null || echo "0")
  importance=${importance:-0}

  local new_importance=$((importance + amount))
  [ "$new_importance" -gt 100 ] && new_importance=100

  _ct_frontmatter_set_raw "$file" "importance" "$new_importance"

  local current_maturity
  current_maturity=$(ct_frontmatter_get "$file" "maturity" 2>/dev/null || echo "draft")
  current_maturity=${current_maturity:-draft}

  local new_maturity
  new_maturity=$(ct_score_maturity "$new_importance" "$current_maturity")

  if [ "$new_maturity" != "$current_maturity" ]; then
    _ct_frontmatter_set_raw "$file" "maturity" "$new_maturity"
  fi
}

# ct_score_recalculate FILE
# Recalculates recency from updatedAt, then evaluates maturity.
ct_score_recalculate() {
  local file=${1:?file required}

  local updated_at
  updated_at=$(ct_frontmatter_get "$file" "updatedAt" 2>/dev/null || echo "")
  if [ -n "$updated_at" ]; then
    local new_recency
    new_recency=$(ct_score_recency "$updated_at")
    _ct_frontmatter_set_raw "$file" "recency" "$new_recency"
  fi

  local importance
  importance=$(ct_frontmatter_get "$file" "importance" 2>/dev/null || echo "0")
  importance=${importance:-0}

  local current_maturity
  current_maturity=$(ct_frontmatter_get "$file" "maturity" 2>/dev/null || echo "draft")
  current_maturity=${current_maturity:-draft}

  local new_maturity
  new_maturity=$(ct_score_maturity "$importance" "$current_maturity")

  if [ "$new_maturity" != "$current_maturity" ]; then
    _ct_frontmatter_set_raw "$file" "maturity" "$new_maturity"
  fi
}

# No-op when sourced; CLI dispatch when executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd=${1:-}
  case "$cmd" in
    recency)     ct_score_recency "${2:?updated_at required}" ;;
    maturity)    ct_score_maturity "${2:?importance required}" "${3:?current_maturity required}" ;;
    apply-event) ct_score_apply_event "${2:?file required}" "${3:?event required}" ;;
    recalculate) ct_score_recalculate "${2:?file required}" ;;
    *)
      echo "Usage: ct-scoring.sh {recency|maturity|apply-event|recalculate} ..." >&2
      exit 1
      ;;
  esac
fi
