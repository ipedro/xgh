#!/usr/bin/env bash
# ct-sync.sh — Orchestration layer: curate, query, refresh
# Sourceable library tying all ct-* libraries together.

_CT_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

type ct_frontmatter_get &>/dev/null || source "${_CT_SYNC_DIR}/ct-frontmatter.sh"
type ct_score_recency &>/dev/null   || source "${_CT_SYNC_DIR}/ct-scoring.sh"
type ct_manifest_add &>/dev/null    || source "${_CT_SYNC_DIR}/ct-manifest.sh"
type ct_archive_run &>/dev/null     || source "${_CT_SYNC_DIR}/ct-archive.sh"
type ct_search_run &>/dev/null      || source "${_CT_SYNC_DIR}/ct-search.sh"

# ct_sync_slugify <string>
# Convert to kebab-case: lowercase, replace non-alphanum with hyphens,
# collapse consecutive hyphens, strip leading/trailing hyphens.
ct_sync_slugify() {
  local input="$1"
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//'
}

# ct_sync_curate <root> <domain> <topic> <title> <content> [tags] [keywords] [source] [from_agent]
ct_sync_curate() {
  local root="${1:?root required}"
  local domain="${2:?domain required}"
  local topic="${3:?topic required}"
  local title="${4:?title required}"
  local content="${5:-}"
  local tags="${6:-}"
  local keywords="${7:-}"
  local source_val="${8:-}"
  local from_agent="${9:-}"

  local slug_domain slug_topic slug_title
  slug_domain=$(ct_sync_slugify "$domain")
  slug_topic=$(ct_sync_slugify "$topic")
  slug_title=$(ct_sync_slugify "$title")

  local rel_path="${slug_domain}/${slug_topic}/${slug_title}.md"
  local dir_path="${root}/${slug_domain}/${slug_topic}"
  local file_path="${dir_path}/${slug_title}.md"

  mkdir -p "$dir_path"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build frontmatter
  {
    echo "---"
    echo "title: ${title}"
    if [[ -n "$tags" ]]; then
      echo "tags: [${tags}]"
    else
      echo "tags: []"
    fi
    if [[ -n "$keywords" ]]; then
      echo "keywords: [${keywords}]"
    else
      echo "keywords: []"
    fi
    echo "importance: 50"
    echo "recency: 1.0000"
    echo "maturity: draft"
    echo "accessCount: 0"
    echo "updateCount: 0"
    echo "createdAt: ${now}"
    echo "updatedAt: ${now}"
    if [[ -n "$source_val" ]]; then
      echo "source: ${source_val}"
    fi
    if [[ -n "$from_agent" ]]; then
      echo "from_agent: ${from_agent}"
    fi
    echo "---"
    echo ""
    echo "$content"
  } > "$file_path"

  ct_manifest_add "$root" "$rel_path"
  ct_manifest_update_indexes "$root"

  echo "$rel_path"
}

# ct_sync_query <root> <query> [top]
ct_sync_query() {
  local root="${1:?root required}"
  local query="${2:-}"
  local top="${3:-10}"

  ct_search_run "$root" "$query" "$top"
}

# ct_sync_refresh <root>
ct_sync_refresh() {
  local root="${1:?root required}"
  ct_manifest_rebuild "$root"
  ct_manifest_update_indexes "$root"
}

# No-op when sourced; CLI dispatch when executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd=${1:-}
  case "$cmd" in
    slugify) ct_sync_slugify "${2:?string required}" ;;
    curate)  shift; ct_sync_curate "$@" ;;
    query)   shift; ct_sync_query "$@" ;;
    refresh) ct_sync_refresh "${2:?root required}" ;;
    *)
      echo "Usage: ct-sync.sh {slugify|curate|query|refresh} ..." >&2
      exit 1
      ;;
  esac
fi
