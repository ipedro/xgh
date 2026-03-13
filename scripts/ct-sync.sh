#!/usr/bin/env bash
# ct-sync.sh — Sync dispatcher: curate, query, score, archive orchestration
# Sourced by context-tree.sh

SCRIPT_DIR_SYNC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

type read_frontmatter_field &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-frontmatter.sh"
type rebuild_manifest &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-manifest.sh"
type cmd_score &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-scoring.sh"
type archive_stale &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-archive.sh"
type cmd_search &>/dev/null || source "${SCRIPT_DIR_SYNC}/ct-search.sh"

cmd_sync() {
  local action=""
  local domain="" topic="" subtopic="" title="" tags="" keywords=""
  local source_val="auto-curate" from_agent="" body="" related=""
  local query="" limit=10 cipher_results=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --action)         action="$2"; shift 2 ;;
      --domain)         domain="$2"; shift 2 ;;
      --topic)          topic="$2"; shift 2 ;;
      --subtopic)       subtopic="$2"; shift 2 ;;
      --title)          title="$2"; shift 2 ;;
      --tags)           tags="$2"; shift 2 ;;
      --keywords)       keywords="$2"; shift 2 ;;
      --source)         source_val="$2"; shift 2 ;;
      --from-agent)     from_agent="$2"; shift 2 ;;
      --body)           body="$2"; shift 2 ;;
      --related)        related="$2"; shift 2 ;;
      --query)          query="$2"; shift 2 ;;
      --limit)          limit="$2"; shift 2 ;;
      --cipher-results) cipher_results="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$action" ]; then
    echo "Error: --action is required (curate|query|score|archive)" >&2
    return 1
  fi

  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"

  case "$action" in
    curate)
      _sync_curate "$ct_dir" "$domain" "$topic" "$subtopic" "$title" \
        "$tags" "$keywords" "$source_val" "$from_agent" "$body" "$related"
      ;;
    query)
      _sync_query "$ct_dir" "$query" "$limit" "$cipher_results"
      ;;
    score)
      cmd_score --all
      ;;
    archive)
      archive_stale "$ct_dir" 35
      ;;
    *)
      echo "Error: unknown action '$action'" >&2
      return 1
      ;;
  esac
}

_sync_curate() {
  local ct_dir="$1" domain="$2" topic="$3" subtopic="$4" title="$5"
  local tags="$6" keywords="$7" source_val="$8" from_agent="$9" body="${10}" related="${11}"

  if [ -z "$domain" ] || [ -z "$title" ]; then
    echo "Error: --domain and --title required for curate" >&2
    return 1
  fi

  local ct_script="${SCRIPT_DIR_SYNC}/context-tree.sh"
  local create_args=(
    create
    --domain "$domain"
    --title "$title"
    --tags "$tags"
    --keywords "$keywords"
    --source "$source_val"
    --from-agent "$from_agent"
    --body "$body"
  )
  [ -n "$topic" ] && create_args+=(--topic "$topic")
  [ -n "$subtopic" ] && create_args+=(--subtopic "$subtopic")
  [ -n "$related" ] && create_args+=(--related "$related")

  bash "$ct_script" "${create_args[@]}"

  local title_slug
  title_slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  local dir_path="${ct_dir}/${domain}"
  [ -n "$topic" ] && dir_path="${dir_path}/${topic}"
  [ -n "$subtopic" ] && dir_path="${dir_path}/${subtopic}"
  local file_path="${dir_path}/${title_slug}.md"

  if [ "$source_val" = "manual" ] && [ -f "$file_path" ]; then
    local imp
    imp=$(read_frontmatter_field "$file_path" "importance")
    imp=${imp:-0}
    local new_imp=$((imp + 10))
    [ "$new_imp" -gt 100 ] && new_imp=100
    update_frontmatter_field "$file_path" "importance" "$new_imp"
  fi

  local rel_path="${domain}"
  [ -n "$topic" ] && rel_path="${rel_path}/${topic}"
  [ -n "$subtopic" ] && rel_path="${rel_path}/${subtopic}"
  rel_path="${rel_path}/${title_slug}.md"

  local importance="10"
  if [ -f "${ct_dir}/${rel_path}" ]; then
    importance=$(read_frontmatter_field "${ct_dir}/${rel_path}" "importance")
  fi

  add_to_manifest "$ct_dir" "$rel_path" "$title" "draft" "$importance"

  generate_index "$ct_dir"

  echo "Curated: ${rel_path}"
}

_sync_query() {
  local ct_dir="$1" query="$2" limit="$3" cipher_results="$4"

  if [ -z "$query" ]; then
    echo "Error: --query required for query action" >&2
    return 1
  fi

  local search_args=(--query "$query" --limit "$limit")
  [ -n "$cipher_results" ] && search_args+=(--cipher-results "$cipher_results")

  cmd_search "${search_args[@]}"
}
