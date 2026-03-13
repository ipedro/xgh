#!/usr/bin/env bash
# ct-frontmatter.sh — YAML frontmatter parse/write helpers for context tree .md files
# Sourced by other scripts; do not execute directly.

# write_frontmatter FILE KEY1 VAL1 KEY2 VAL2 ...
# Prepends YAML frontmatter to FILE. Preserves existing body content.
# Auto-adds createdAt and updatedAt timestamps.
write_frontmatter() {
  local file="$1"; shift
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Read existing body (strip any existing frontmatter)
  local body=""
  if [ -f "$file" ]; then
    body=$(read_frontmatter_body "$file")
  fi

  # Build frontmatter
  {
    echo "---"
    local has_created=0 has_updated=0
    while [ $# -ge 2 ]; do
      local key="$1" val="$2"; shift 2
      echo "${key}: ${val}"
      [ "$key" = "createdAt" ] && has_created=1
      [ "$key" = "updatedAt" ] && has_updated=1
    done
    [ "$has_created" -eq 0 ] && echo "createdAt: ${now}"
    [ "$has_updated" -eq 0 ] && echo "updatedAt: ${now}"
    echo "---"
    echo ""
    echo "$body"
  } > "$file"
}

# read_frontmatter_field FILE FIELD
# Prints the value of FIELD from YAML frontmatter. Empty string if not found.
read_frontmatter_field() {
  local file="$1" field="$2"
  if [ ! -f "$file" ]; then echo ""; return; fi

  # Check if file starts with ---
  local first_line
  first_line=$(head -n 1 "$file")
  if [ "$first_line" != "---" ]; then echo ""; return; fi

  # Extract frontmatter block (between first and second ---)
  awk '
    BEGIN { in_fm=0; count=0 }
    /^---$/ { count++; if (count==1) { in_fm=1; next } else { exit } }
    in_fm { print }
  ' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}: *//"
}

# read_frontmatter_body FILE
# Prints everything after the closing --- of frontmatter.
# If no frontmatter, prints entire file.
read_frontmatter_body() {
  local file="$1"
  if [ ! -f "$file" ]; then echo ""; return; fi

  local first_line
  first_line=$(head -n 1 "$file")
  if [ "$first_line" != "---" ]; then
    cat "$file"
    return
  fi

  # Skip frontmatter, print rest
  awk '
    BEGIN { count=0; past_fm=0 }
    /^---$/ { count++; if (count==2) { past_fm=1; next } next }
    past_fm { print }
  ' "$file"
}

# update_frontmatter_field FILE FIELD NEW_VALUE
# Updates a single field in existing frontmatter. Also bumps updatedAt.
update_frontmatter_field() {
  local file="$1" field="$2" new_val="$3"
  if [ ! -f "$file" ]; then return 1; fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local tmpfile
  tmpfile=$(mktemp)

  awk -v field="$field" -v val="$new_val" -v now="$now" '
    BEGIN { in_fm=0; count=0; found=0; updated_ts=0 }
    /^---$/ {
      count++
      if (count == 2 && !found) {
        print field ": " val
      }
      if (count == 2 && !updated_ts) {
        print "updatedAt: " now
      }
      print
      next
    }
    count == 1 && $0 ~ "^" field ": " {
      print field ": " val
      found = 1
      next
    }
    count == 1 && $0 ~ "^updatedAt: " {
      print "updatedAt: " now
      updated_ts = 1
      next
    }
    { print }
  ' "$file" > "$tmpfile"

  mv "$tmpfile" "$file"
}

# has_frontmatter FILE
# Returns 0 if file has YAML frontmatter, 1 otherwise.
has_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 1
  local first_line
  first_line=$(head -n 1 "$file")
  [ "$first_line" = "---" ]
}

# list_frontmatter_fields FILE
# Prints all field names from frontmatter, one per line.
list_frontmatter_fields() {
  local file="$1"
  if ! has_frontmatter "$file"; then return; fi
  awk '
    BEGIN { count=0 }
    /^---$/ { count++; if (count>=2) exit; next }
    count==1 { split($0, a, ":"); print a[1] }
  ' "$file"
}
