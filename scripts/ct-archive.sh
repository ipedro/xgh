#!/usr/bin/env bash
# ct-archive.sh — Archive low-importance drafts, restore archived files
# Sourced by context-tree.sh

archive_single() {
  local ct_dir="$1" rel_path="$2"
  local source_file="${ct_dir}/${rel_path}.md"

  if [ ! -f "$source_file" ]; then
    echo "Error: file not found: ${source_file}" >&2
    return 1
  fi

  local archive_dir="${ct_dir}/_archived/$(dirname "$rel_path")"
  mkdir -p "$archive_dir"

  local basename
  basename=$(basename "$rel_path")

  cp "$source_file" "${archive_dir}/${basename}.full.md"

  local stub_file="${ct_dir}/$(dirname "$rel_path")/${basename}.stub.md"

  local title tags keywords importance maturity created_at
  title=$(read_frontmatter_field "$source_file" "title")
  tags=$(read_frontmatter_field "$source_file" "tags")
  keywords=$(read_frontmatter_field "$source_file" "keywords")
  importance=$(read_frontmatter_field "$source_file" "importance")
  maturity=$(read_frontmatter_field "$source_file" "maturity")
  created_at=$(read_frontmatter_field "$source_file" "createdAt")

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$stub_file" << STUBEOF
---
title: ${title}
tags: ${tags}
keywords: ${keywords}
importance: ${importance}
maturity: ${maturity}
archived: true
archivedAt: ${now}
archivePath: _archived/${rel_path}.full.md
createdAt: ${created_at}
updatedAt: ${now}
---

**ARCHIVED** — This entry was archived due to low importance. Use \`context-tree.sh archive --restore "${rel_path}"\` to restore.
STUBEOF

  rm "$source_file"

  echo "Archived: ${rel_path}"
}

archive_stale() {
  local ct_dir="$1"
  local threshold="${2:-35}"

  find "$ct_dir" -name "*.md" \
    ! -name "_index.md" \
    ! -name "context.md" \
    ! -name "*.stub.md" \
    ! -path "*/_archived/*" \
    -type f | while read -r file; do

    local maturity importance
    maturity=$(read_frontmatter_field "$file" "maturity")
    importance=$(read_frontmatter_field "$file" "importance")
    maturity=${maturity:-draft}
    importance=${importance:-0}

    if [ "$maturity" = "draft" ] && [ "$importance" -lt "$threshold" ]; then
      local rel_path="${file#${ct_dir}/}"
      rel_path="${rel_path%.md}"
      archive_single "$ct_dir" "$rel_path"
    fi
  done
}

restore_archived() {
  local ct_dir="$1" rel_path="$2"

  local basename
  basename=$(basename "$rel_path")
  local dir_part
  dir_part=$(dirname "$rel_path")

  local archive_file="${ct_dir}/_archived/${dir_part}/${basename}.full.md"
  local stub_file="${ct_dir}/${dir_part}/${basename}.stub.md"
  local target_file="${ct_dir}/${rel_path}.md"

  if [ ! -f "$archive_file" ]; then
    echo "Error: archive not found: ${archive_file}" >&2
    return 1
  fi

  mkdir -p "$(dirname "$target_file")"

  cp "$archive_file" "$target_file"

  [ -f "$stub_file" ] && rm "$stub_file"
  rm "$archive_file"

  local arch_dir
  arch_dir=$(dirname "$archive_file")
  while [ "$arch_dir" != "${ct_dir}/_archived" ] && [ -d "$arch_dir" ]; do
    if [ -z "$(ls -A "$arch_dir" 2>/dev/null)" ]; then
      rmdir "$arch_dir"
      arch_dir=$(dirname "$arch_dir")
    else
      break
    fi
  done

  echo "Restored: ${rel_path}"
}

cmd_archive() {
  local ct_dir="${XGH_CONTEXT_TREE_DIR:-${PWD}/.xgh/context-tree}"
  local action="stale" threshold=35 restore_path=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --stale)     action="stale"; shift ;;
      --threshold) threshold="$2"; shift 2 ;;
      --restore)   action="restore"; restore_path="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  case "$action" in
    stale)   archive_stale "$ct_dir" "$threshold" ;;
    restore) restore_archived "$ct_dir" "$restore_path" ;;
  esac
}
