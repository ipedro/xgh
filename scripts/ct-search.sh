#!/usr/bin/env bash
# ct-search.sh — BM25 search + optional merge with Cipher results
# Sourced by context-tree.sh

cmd_search() {
  local query="" limit=10 cipher_results=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --query)          query="$2"; shift 2 ;;
      --limit)          limit="$2"; shift 2 ;;
      --cipher-results) cipher_results="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$query" ]; then
    echo "Error: --query is required" >&2; return 1
  fi

  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local bm25_json
  bm25_json=$(python3 "${script_dir}/bm25.py" "$ct_dir" "$query" "$limit")

  if [ -z "$cipher_results" ]; then
    echo "$bm25_json" | python3 -c "
import json, sys

bm25 = json.load(sys.stdin)
limit = int('$limit')

results = []
for r in bm25:
    imp_norm = r['importance'] / 100.0
    rec = r['recency']
    bm25_s = r['bm25_score']
    maturity_boost = 1.15 if r['maturity'] == 'core' else 1.0

    score = (0.6 * bm25_s + 0.2 * imp_norm + 0.2 * rec) * maturity_boost
    r['final_score'] = round(score, 4)
    results.append(r)

results.sort(key=lambda x: x['final_score'], reverse=True)
for r in results[:limit]:
    mat_tag = f'[{r[\"maturity\"]}]'
    print(f'{r[\"final_score\"]:.3f}  {mat_tag:12s}  {r[\"path\"]:60s}  {r[\"title\"]}')
"
  else
    echo "$bm25_json" | python3 -c "
import json, sys

bm25 = json.load(sys.stdin)
limit = int('$limit')
cipher = json.loads('''$cipher_results''')

cipher_map = {}
for c in cipher:
    key = c.get('path', c.get('title', ''))
    cipher_map[key] = c.get('similarity', 0)

results = []
for r in bm25:
    cipher_sim = cipher_map.get(r['path'], 0)
    imp_norm = r['importance'] / 100.0
    rec = r['recency']
    bm25_s = r['bm25_score']
    maturity_boost = 1.15 if r['maturity'] == 'core' else 1.0

    score = (0.5 * cipher_sim + 0.3 * bm25_s + 0.1 * imp_norm + 0.1 * rec) * maturity_boost
    r['cipher_similarity'] = cipher_sim
    r['final_score'] = round(score, 4)
    results.append(r)

bm25_paths = {r['path'] for r in bm25}
for c in cipher:
    path = c.get('path', '')
    if path and path not in bm25_paths:
        score = (0.5 * c.get('similarity', 0)) * 1.0
        results.append({
            'path': path,
            'title': c.get('title', ''),
            'cipher_similarity': c.get('similarity', 0),
            'bm25_score': 0,
            'final_score': round(score, 4),
            'maturity': 'unknown',
        })

results.sort(key=lambda x: x['final_score'], reverse=True)
for r in results[:limit]:
    mat_tag = f'[{r.get(\"maturity\", \"?\")}]'
    print(f'{r[\"final_score\"]:.3f}  {mat_tag:12s}  {r[\"path\"]:60s}  {r.get(\"title\", \"\")}')
"
  fi
}
