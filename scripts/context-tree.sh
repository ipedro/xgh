#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/ct-frontmatter.sh"
CT_DIR="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"
slugify() { echo "$1"|tr '[:upper:]' '[:lower:]'|sed 's/[^a-z0-9]/-/g'|sed 's/--*/-/g'|sed 's/^-//;s/-$//'; }
format_tags() { echo "[$(echo "$1"|sed 's/,/, /g')]"; }
resolve_path() {
  local d="${CT_DIR}/$1"; [ -n "${2:-}" ] && d="$d/$2"; [ -n "${3:-}" ] && d="$d/$3"; echo "$d/$4.md"
}
cmd_create() {
  local domain="" topic="" subtopic="" title="" tags="" keywords="" source="auto-curate" from_agent="" body="" related=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;; --topic) topic="$2"; shift 2 ;; --subtopic) subtopic="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;; --tags) tags="$2"; shift 2 ;; --keywords) keywords="$2"; shift 2 ;;
      --source) source="$2"; shift 2 ;; --from-agent) from_agent="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;; --related) related="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  [ -z "$domain" ] && { echo "Error: --domain required" >&2; exit 1; }
  [ -z "$title" ] && { echo "Error: --title required" >&2; exit 1; }
  local ts; ts=$(slugify "$title")
  local fp; fp=$(resolve_path "$domain" "$topic" "$subtopic" "$ts")
  [ -f "$fp" ] && { echo "Error: file already exists: ${fp}" >&2; exit 1; }
  mkdir -p "$(dirname "$fp")"
  echo "$body" > "$fp"
  local fa=("title" "$title" "tags" "$(format_tags "$tags")" "keywords" "$(format_tags "$keywords")" "importance" "10" "recency" "1.0" "maturity" "draft" "accessCount" "0" "updateCount" "0" "source" "$source" "fromAgent" "$from_agent")
  [ -n "$related" ] && fa+=("related" "$related")
  write_frontmatter "$fp" "${fa[@]}"
  echo "Created: ${fp}"
}
cmd_read() {
  local path=""
  while [ $# -gt 0 ]; do case "$1" in --path) path="$2"; shift 2 ;; *) echo "Unknown: $1" >&2; exit 1 ;; esac; done
  [ -z "$path" ] && { echo "Error: --path required" >&2; exit 1; }
  local fp="${CT_DIR}/${path}.md"
  [ ! -f "$fp" ] && { echo "Error: not found: ${fp}" >&2; exit 1; }
  local c; c=$(read_frontmatter_field "$fp" "accessCount"); c=${c:-0}
  update_frontmatter_field "$fp" "accessCount" "$((c + 1))"
  local i; i=$(read_frontmatter_field "$fp" "importance"); i=${i:-0}
  local ni=$((i + 3)); [ "$ni" -gt 100 ] && ni=100
  update_frontmatter_field "$fp" "importance" "$ni"
  cat "$fp"
}
cmd_list() {
  local domain=""
  while [ $# -gt 0 ]; do case "$1" in --domain) domain="$2"; shift 2 ;; *) echo "Unknown: $1" >&2; exit 1 ;; esac; done
  local sd="$CT_DIR"; [ -n "$domain" ] && sd="${CT_DIR}/${domain}"
  [ ! -d "$sd" ] && { echo "No files found."; return 0; }
  find "$sd" -name "*.md" ! -name "_index.md" ! -name "context.md" ! -name "*.stub.md" -type f | sort | while read -r f; do
    local rp="${f#${CT_DIR}/}"
    local t m i
    t=$(read_frontmatter_field "$f" "title"); m=$(read_frontmatter_field "$f" "maturity"); i=$(read_frontmatter_field "$f" "importance")
    printf "%-60s  [%s]  imp:%s\n" "$rp" "${m:-unknown}" "${i:-0}"
  done
}
cmd_update() {
  local path="" body="" tags="" keywords="" title="" related=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --path) path="$2"; shift 2 ;; --body) body="$2"; shift 2 ;; --tags) tags="$2"; shift 2 ;;
      --keywords) keywords="$2"; shift 2 ;; --title) title="$2"; shift 2 ;; --related) related="$2"; shift 2 ;;
      *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
  done
  [ -z "$path" ] && { echo "Error: --path required" >&2; exit 1; }
  local fp="${CT_DIR}/${path}.md"
  [ ! -f "$fp" ] && { echo "Error: not found: ${fp}" >&2; exit 1; }
  if [ -n "$body" ]; then
    local tf; tf=$(mktemp)
    awk 'BEGIN{c=0}/^---$/{c++;print;if(c>=2)exit;next}c>=1&&c<2{print}' "$fp" > "$tf"
    echo "" >> "$tf"; echo "$body" >> "$tf"; mv "$tf" "$fp"
  fi
  [ -n "$tags" ] && update_frontmatter_field "$fp" "tags" "$(format_tags "$tags")"
  [ -n "$keywords" ] && update_frontmatter_field "$fp" "keywords" "$(format_tags "$keywords")"
  [ -n "$title" ] && update_frontmatter_field "$fp" "title" "$title"
  [ -n "$related" ] && update_frontmatter_field "$fp" "related" "$related"
  local uc; uc=$(read_frontmatter_field "$fp" "updateCount"); uc=${uc:-0}
  update_frontmatter_field "$fp" "updateCount" "$((uc + 1))"
  local i; i=$(read_frontmatter_field "$fp" "importance"); i=${i:-0}
  local ni=$((i + 5)); [ "$ni" -gt 100 ] && ni=100
  update_frontmatter_field "$fp" "importance" "$ni"
  update_frontmatter_field "$fp" "recency" "1.0"
  echo "Updated: ${fp}"
}
cmd_delete() {
  local path=""
  while [ $# -gt 0 ]; do case "$1" in --path) path="$2"; shift 2 ;; *) echo "Unknown: $1" >&2; exit 1 ;; esac; done
  [ -z "$path" ] && { echo "Error: --path required" >&2; exit 1; }
  local fp="${CT_DIR}/${path}.md"
  # If primary file missing, check archived counterparts
  if [ ! -f "$fp" ]; then
    local stub="${CT_DIR}/_archived/${path}.stub.md"
    local full="${CT_DIR}/_archived/${path}.full.md"
    if [ -f "$stub" ] || [ -f "$full" ]; then
      rm -f "$stub" "$full"
      echo "Deleted archived: ${path}"; return 0
    fi
    echo "Error: not found: ${fp}" >&2; exit 1
  fi
  rm "$fp"
  # Also remove any archived counterparts
  rm -f "${CT_DIR}/_archived/${path}.stub.md" 2>/dev/null || true
  rm -f "${CT_DIR}/_archived/${path}.full.md" 2>/dev/null || true
  local d; d=$(dirname "$fp")
  while [ "$d" != "$CT_DIR" ] && [ -d "$d" ]; do
    [ -z "$(ls -A "$d" 2>/dev/null)" ] && { rmdir "$d"; d=$(dirname "$d"); } || break
  done
  echo "Deleted: ${path}"
}
if [ $# -lt 1 ]; then echo "Usage: context-tree.sh <command>"; exit 1; fi
CMD="$1"; shift
case "$CMD" in
  create)  cmd_create "$@" ;;
  read)    cmd_read "$@" ;;
  list)    cmd_list "$@" ;;
  update)  cmd_update "$@" ;;
  delete)  cmd_delete "$@" ;;
  search)  source "${SCRIPT_DIR}/ct-search.sh"; cmd_search "$@" ;;
  score)   source "${SCRIPT_DIR}/ct-scoring.sh"; cmd_score "$@" ;;
  archive) source "${SCRIPT_DIR}/ct-archive.sh"; cmd_archive "$@" ;;
  sync)    source "${SCRIPT_DIR}/ct-sync.sh"; cmd_sync "$@" ;;
  *) echo "Unknown command: $CMD" >&2; exit 1 ;;
esac
