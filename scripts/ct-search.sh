#!/usr/bin/env bash
# ct-search.sh — BM25 search library
# Sourceable library providing ct_search_run function.

_CT_SEARCH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ct_search_run <root> <query> [top]
# BM25-only search with scoring formula:
#   final_score = (0.6 × bm25 + 0.2 × importance/100 + 0.2 × recency) × maturityBoost
# Outputs JSON array sorted by final_score descending.
ct_search_run() {
  local root="$1" query="$2" top="${3:-10}"

  if [ -z "$query" ]; then
    echo "[]"
    return 0
  fi

  local bm25_json
  bm25_json=$(python3 "${_CT_SEARCH_SCRIPT_DIR}/bm25.py" "$root" "$query" "$top")

  echo "$bm25_json" | python3 -c "
import json, sys

bm25 = json.load(sys.stdin)
limit = int('$top')

results = []
for r in bm25:
    imp_norm = r['importance'] / 100.0
    rec = r['recency']
    bm25_s = r['bm25_score']
    maturity_boost = 1.15 if r.get('maturity', 'draft') == 'core' else 1.0

    score = (0.6 * bm25_s + 0.2 * imp_norm + 0.2 * rec) * maturity_boost
    r['final_score'] = round(score, 4)
    results.append(r)

results.sort(key=lambda x: x['final_score'], reverse=True)
print(json.dumps(results[:limit], indent=2))
"
}
