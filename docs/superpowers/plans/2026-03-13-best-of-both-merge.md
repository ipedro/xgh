# Best-of-Both Script Merge — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite xgh's 7 shell scripts + 2 hooks to combine Copilot's sourceable library architecture with our functional wins (hysteresis scoring, dual BM25+Cipher search, field-weighted BM25).

**Architecture:** All `ct-*.sh` scripts become sourceable libraries with `BASH_SOURCE[0]` CLI guards. `context-tree.sh` sources them all and dispatches CLI subcommands. Manifest switches from nested `domains[].topics[]` to flat `entries[]`. Hooks output structured JSON.

**Tech Stack:** Bash, AWK, Python 3 (for scoring math, JSON manipulation, BM25), Claude Code hooks

**Spec:** `docs/superpowers/specs/2026-03-13-best-of-both-merge.md`

**Reference implementations:**
- Copilot branch (structure): `git show origin/copilot/update-readme-positioning:<path>`
- Our branch (functionality): current files on `feat/initial-release`

---

## Chunk 1: Foundation Libraries

### Task 1: ct-frontmatter.sh — YAML frontmatter parser

**Files:**
- Create: `scripts/ct-frontmatter.sh` (overwrite existing)
- Create: `tests/test-ct-frontmatter.sh` (overwrite existing)

**Reference:** `git show origin/copilot/update-readme-positioning:scripts/ct-frontmatter.sh` for the AWK-based parsing pattern.

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/ct-frontmatter.sh"

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

# --- ct_frontmatter_has ---
cat > "$TMP/with_fm.md" <<'EOF'
---
title: Test
importance: 50
---
Body content here
EOF

cat > "$TMP/no_fm.md" <<'EOF'
Just some text without frontmatter
EOF

ct_frontmatter_has "$TMP/with_fm.md" && assert_eq "has: with frontmatter" "0" "0" || assert_eq "has: with frontmatter" "0" "1"
ct_frontmatter_has "$TMP/no_fm.md" && assert_eq "has: without frontmatter" "1" "0" || assert_eq "has: without frontmatter" "0" "0"

# --- ct_frontmatter_get ---
assert_eq "get title" "Test" "$(ct_frontmatter_get "$TMP/with_fm.md" "title")"
assert_eq "get importance" "50" "$(ct_frontmatter_get "$TMP/with_fm.md" "importance")"
assert_eq "get missing key" "" "$(ct_frontmatter_get "$TMP/with_fm.md" "nonexistent" || true)"

# --- ct_frontmatter_set ---
ct_frontmatter_set "$TMP/with_fm.md" "importance" "75"
assert_eq "set importance" "75" "$(ct_frontmatter_get "$TMP/with_fm.md" "importance")"

# set new key
ct_frontmatter_set "$TMP/with_fm.md" "maturity" "validated"
assert_eq "set new key" "validated" "$(ct_frontmatter_get "$TMP/with_fm.md" "maturity")"

# body preserved after set
grep -q "Body content here" "$TMP/with_fm.md" && assert_eq "body preserved" "0" "0" || assert_eq "body preserved" "0" "1"

# updatedAt auto-set
UPDATED=$(ct_frontmatter_get "$TMP/with_fm.md" "updatedAt")
[ -n "$UPDATED" ] && assert_eq "updatedAt set" "0" "0" || assert_eq "updatedAt set" "0" "1"

# --- ct_frontmatter_increment_int ---
ct_frontmatter_set "$TMP/with_fm.md" "accessCount" "5"
ct_frontmatter_increment_int "$TMP/with_fm.md" "accessCount"
assert_eq "increment int" "6" "$(ct_frontmatter_get "$TMP/with_fm.md" "accessCount")"

# increment from 0
ct_frontmatter_set "$TMP/with_fm.md" "updateCount" "0"
ct_frontmatter_increment_int "$TMP/with_fm.md" "updateCount"
assert_eq "increment from 0" "1" "$(ct_frontmatter_get "$TMP/with_fm.md" "updateCount")"

# --- tags/keywords (array values) ---
cat > "$TMP/arrays.md" <<'EOF'
---
title: Arrays Test
tags: [auth, jwt]
keywords: [token, refresh]
---
EOF

assert_eq "get tags" "[auth, jwt]" "$(ct_frontmatter_get "$TMP/arrays.md" "tags")"
assert_eq "get keywords" "[token, refresh]" "$(ct_frontmatter_get "$TMP/arrays.md" "keywords")"

# --- quoted values ---
cat > "$TMP/quoted.md" <<'EOF'
---
title: "Quoted Title"
---
EOF

assert_eq "get quoted title" "Quoted Title" "$(ct_frontmatter_get "$TMP/quoted.md" "title")"

echo "Frontmatter tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-ct-frontmatter.sh
```
Expected: FAIL — functions not defined yet.

- [ ] **Step 3: Write ct-frontmatter.sh**

Create `scripts/ct-frontmatter.sh` — sourceable library with AWK-based parsing. Reference Copilot's `ct_frontmatter_has`, `ct_frontmatter_get`, `ct_frontmatter_set` pattern. Add `ct_frontmatter_increment_int` (new).

Key implementation notes:
- `ct_frontmatter_get`: AWK that finds `key:` in the `---` block, strips quotes
- `ct_frontmatter_set`: AWK that replaces existing key or appends before closing `---`. Always updates `updatedAt` field. Uses `mktemp` + `mv` for atomicity.
- `ct_frontmatter_increment_int`: calls `get`, increments, calls `set`
- `BASH_SOURCE[0]` guard at bottom (no-op since it's library-only)

- [ ] **Step 4: Run test — verify it passes**

```bash
bash tests/test-ct-frontmatter.sh
```
Expected: All ~14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ct-frontmatter.sh tests/test-ct-frontmatter.sh
git commit -m "feat: rewrite ct-frontmatter.sh as sourceable library"
```

---

### Task 2: ct-scoring.sh — importance/recency/maturity scoring

**Files:**
- Create: `scripts/ct-scoring.sh` (overwrite existing)
- Create: `tests/test-ct-scoring.sh` (overwrite existing)

**Depends on:** Task 1 (ct-frontmatter.sh)

- [ ] **Step 1: Write the test file**

```bash
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

# --- ct_score_recency ---
# 0 days ago → recency 1.0
RECENCY=$(ct_score_recency "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
assert_eq "recency today" "1.0000" "$RECENCY"

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

echo "Scoring tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-ct-scoring.sh
```
Expected: FAIL.

- [ ] **Step 3: Write ct-scoring.sh**

Create `scripts/ct-scoring.sh` — sourceable library. Source `ct-frontmatter.sh`. Named constants at top. Functions:
- `ct_score_recency <updated_at>` — Python one-liner for `exp(-ln(2) * days / 21)`
- `ct_score_maturity <importance> <current_maturity>` — bash arithmetic with hysteresis thresholds
- `ct_score_recalculate <file>` — reads fields, calls recency + maturity, writes back
- `ct_score_apply_event <file> <event>` — bumps importance by event amount (3/5/10), caps at 100, calls `ct_score_maturity` and writes new maturity. Does NOT touch updatedAt/recency.

- [ ] **Step 4: Run test — verify it passes**

```bash
bash tests/test-ct-scoring.sh
```
Expected: All ~15 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ct-scoring.sh tests/test-ct-scoring.sh
git commit -m "feat: rewrite ct-scoring.sh with hysteresis and named constants"
```

---

## Chunk 2: Data Layer Libraries

### Task 3: ct-manifest.sh — flat manifest management

**Files:**
- Create: `scripts/ct-manifest.sh` (overwrite existing)
- Create: `tests/test-ct-manifest.sh` (overwrite existing)

**Depends on:** Task 1 (ct-frontmatter.sh)

- [ ] **Step 1: Write the test file**

Tests must verify:
- `ct_manifest_init` creates valid JSON with `entries: []`
- `ct_manifest_add` upserts entry by reading frontmatter from file
- `ct_manifest_remove` deletes entry by path
- `ct_manifest_rebuild` scans filesystem and rebuilds
- `ct_manifest_list` outputs entry paths
- `ct_manifest_update_indexes` generates `_index.md` per domain directory
- Schema is flat `entries[]` (no `domains[]`)

Test pattern: create a temp context tree with 3-4 entries across 2 domains, run each function, verify JSON output with `python3 -c "import json; ..."`.

~14 assertions following the same `assert_eq` pattern.

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-ct-manifest.sh
```

- [ ] **Step 3: Write ct-manifest.sh**

Sourceable library. Python heredocs for JSON manipulation (same pattern as Copilot). Functions:
- `ct_manifest_init <root>` — creates `_manifest.json` with `{"version":"1.0.0","team":"${XGH_TEAM:-my-team}","created":"...","entries":[]}`
- `ct_manifest_add <root> <rel-path>` — reads frontmatter from file, upserts into entries array
- `ct_manifest_remove <root> <rel-path>` — filters out entry by path
- `ct_manifest_rebuild <root>` — `find` all `.md` files, parse frontmatter, rebuild entries
- `ct_manifest_list <root>` — Python reads manifest, prints paths
- `ct_manifest_update_indexes <root>` — Python generates `_index.md` per first-level directory

- [ ] **Step 4: Run test — verify it passes**

```bash
bash tests/test-ct-manifest.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/ct-manifest.sh tests/test-ct-manifest.sh
git commit -m "feat: rewrite ct-manifest.sh with flat entries schema"
```

---

### Task 4: ct-archive.sh — archival system

**Files:**
- Create: `scripts/ct-archive.sh` (overwrite existing)
- Create: `tests/test-ct-archive.sh` (overwrite existing)

**Depends on:** Tasks 1, 3 (ct-frontmatter.sh, ct-manifest.sh)

- [ ] **Step 1: Write the test file**

Tests must verify:
- `ct_archive_run` archives draft entries with importance < 35
- Creates `.full.md` and `.stub.md` in `_archived/`
- Does NOT archive validated/core entries
- Does NOT archive drafts with importance >= 35
- `ct_archive_restore` copies `.full.md` back and updates manifest
- Restored file has correct frontmatter
- Archived count reported correctly

~15 assertions.

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-ct-archive.sh
```

- [ ] **Step 3: Write ct-archive.sh**

Sourceable library. Reference Copilot's `ct_archive_run`/`ct_archive_restore` pattern. Source `ct-frontmatter.sh` and `ct-manifest.sh`.

- [ ] **Step 4: Run test — verify it passes**

```bash
bash tests/test-ct-archive.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/ct-archive.sh tests/test-ct-archive.sh
git commit -m "feat: rewrite ct-archive.sh as sourceable library"
```

---

### Task 5: ct-search.sh — dual-mode BM25+Cipher search

**Files:**
- Create: `scripts/ct-search.sh` (overwrite existing)
- Create: `tests/test-ct-search.sh` (overwrite existing)

**Depends on:** bm25.py (unchanged)

- [ ] **Step 1: Write the test file**

Tests must verify:
- `ct_search_run` returns results for matching query
- Results include `bm25_score`, `final_score`, `path`, `title`, `maturity`
- Results sorted by `final_score` descending
- Maturity boost applied (core entries score higher)
- `ct_search_with_cipher` merges Cipher results (mock JSON input)
- Empty query returns empty results

~8 assertions. Create a temp context tree with 3 entries, search for a term that appears in one.

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-ct-search.sh
```

- [ ] **Step 3: Write ct-search.sh**

Sourceable library. Two functions:
- `ct_search_run <root> <query> [top]` — calls `python3 bm25.py`, pipes through Python scoring post-processor with formula `(0.6 × bm25 + 0.2 × importance/100 + 0.2 × recency) × maturityBoost`
- `ct_search_with_cipher <root> <query> <cipher_json> [top]` — same but uses `(0.5 × cipher + 0.3 × bm25 + 0.1 × importance/100 + 0.1 × recency) × maturityBoost`

- [ ] **Step 4: Run test — verify it passes**

```bash
bash tests/test-ct-search.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/ct-search.sh tests/test-ct-search.sh
git commit -m "feat: rewrite ct-search.sh with dual BM25+Cipher mode"
```

---

## Chunk 3: Orchestration + CLI + Hooks

### Task 6: ct-sync.sh — orchestration layer

**Files:**
- Create: `scripts/ct-sync.sh` (overwrite existing)
- Create: `tests/test-ct-sync.sh` (overwrite existing)

**Depends on:** Tasks 1-5 (all libraries)

- [ ] **Step 1: Write the test file**

Tests must verify:
- `ct_sync_slugify` converts strings to kebab-case
- `ct_sync_curate` creates entry at correct path with correct frontmatter
- `ct_sync_query` delegates to search and returns results
- `ct_sync_refresh` rebuilds manifest and indexes

~11 assertions.

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-ct-sync.sh
```

- [ ] **Step 3: Write ct-sync.sh**

Sourceable library. Source all `ct-*.sh` libraries. Functions:
- `ct_sync_slugify <string>` — `tr` + `sed` to kebab-case
- `ct_sync_curate <root> <domain> <topic> <title> <content> [tags] [keywords] [source] [from_agent]` — builds rel-path via slugify, creates file with frontmatter, calls manifest_add + update_indexes
- `ct_sync_query <root> <query> [cipher_json] [top]` — delegates to `ct_search_run` or `ct_search_with_cipher`
- `ct_sync_refresh <root>` — calls `ct_manifest_rebuild` + `ct_manifest_update_indexes`

- [ ] **Step 4: Run test — verify it passes**

```bash
bash tests/test-ct-sync.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/ct-sync.sh tests/test-ct-sync.sh
git commit -m "feat: rewrite ct-sync.sh as sourceable orchestration library"
```

---

### Task 7: context-tree.sh — CLI dispatcher + tests

**Files:**
- Create: `scripts/context-tree.sh` (overwrite existing)
- Create: `tests/test-ct-crud.sh` (overwrite existing)
- Delete: `tests/test-ct-core.sh` (merged into test-ct-crud.sh)

**Depends on:** Tasks 1-6 (all libraries)

- [ ] **Step 1: Write the test file (test-ct-crud.sh)**

Tests must verify the CLI interface end-to-end:
- `context-tree.sh init` creates directory + manifest
- `context-tree.sh create backend/auth/jwt.md "JWT Patterns" "content"` creates file with frontmatter
- `context-tree.sh read backend/auth/jwt.md` outputs content, bumps accessCount
- `context-tree.sh update backend/auth/jwt.md "new content"` appends update section
- `context-tree.sh delete backend/auth/jwt.md` removes file + cleans dirs
- `context-tree.sh list` shows entries
- `context-tree.sh search "jwt"` returns matching results
- `context-tree.sh score backend/auth/jwt.md search-hit` bumps importance
- Delete also checks `_archived/` counterparts

~25 assertions using `XGH_CONTEXT_TREE="$TMP"` to isolate.

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-ct-crud.sh
```

- [ ] **Step 3: Write context-tree.sh**

Sources all libraries. Sets `CT_ROOT=${XGH_CONTEXT_TREE:-.xgh/context-tree}`. Parses `$1` as subcommand, dispatches to library functions. Reference the spec's subcommand details for exact behavior.

`BASH_SOURCE[0]` guard: the `main()` dispatch only runs when executed directly, not when sourced.

- [ ] **Step 4: Run test — verify it passes**

```bash
bash tests/test-ct-crud.sh
```

- [ ] **Step 5: Delete test-ct-core.sh and commit**

```bash
rm -f tests/test-ct-core.sh
git add scripts/context-tree.sh tests/test-ct-crud.sh
git rm -f tests/test-ct-core.sh 2>/dev/null || true
git commit -m "feat: rewrite context-tree.sh as CLI dispatcher over library functions"
```

---

### Task 8: Hooks — session-start.sh + prompt-submit.sh

**Files:**
- Create: `hooks/session-start.sh` (overwrite existing)
- Create: `hooks/prompt-submit.sh` (overwrite existing)
- Modify: `tests/test-hooks.sh`

**Depends on:** None (hooks are standalone Python-in-bash)

- [ ] **Step 1: Write the updated test file**

Update `tests/test-hooks.sh` to validate new JSON structure:
- session-start outputs valid JSON with `result`, `contextFiles`, `decisionTable`, `briefingTrigger` keys
- `contextFiles` is an array of objects with `path`, `title`, `importance`, `maturity`, `excerpt`
- `decisionTable` is an array of strings
- `briefingTrigger` reflects `XGH_BRIEFING` env var
- prompt-submit outputs valid JSON with `result`, `promptIntent`, `requiredActions`, `toolHints`
- `promptIntent` is `code-change` for code-related prompts, `general` otherwise
- Both hooks exit 0

~15 assertions.

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-hooks.sh
```

- [ ] **Step 3: Write session-start.sh**

Pure Python heredoc. Walks `XGH_CONTEXT_TREE` directory via `rglob("*.md")`. For each file: parse frontmatter, compute score = `maturity_rank × 100 + importance`. Select top 5. Extract 3-line excerpt. Build JSON with `contextFiles`, `decisionTable`, `briefingTrigger`. Exclude `_index.md` and `_archived/`.

Reference Copilot's `hooks/session-start.sh` for the Python structure and JSON output pattern.

- [ ] **Step 4: Write prompt-submit.sh**

Copy from Copilot branch: `git show origin/copilot/update-readme-positioning:hooks/prompt-submit.sh`. This is already the correct implementation (intent detection + structured JSON).

- [ ] **Step 5: Run test — verify it passes**

```bash
bash tests/test-hooks.sh
```

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start.sh hooks/prompt-submit.sh tests/test-hooks.sh
git commit -m "feat: rewrite hooks with structured JSON output and intent detection"
```

---

## Chunk 4: Light-Touch Updates + Integration

### Task 9: Light-touch file updates

**Files:**
- Modify: `install.sh` — change `"domains": []` to `"entries": []`, rename `XGH_CONTEXT_PATH` to `XGH_CONTEXT_TREE`
- Modify: `scripts/configure.sh` — produce flat `entries[]` manifest
- Modify: `commands/query.md` — rename env var
- Modify: `commands/status.md` — rename env var

- [ ] **Step 1: Update install.sh**

In `install.sh`:
1. Line 6: Change `XGH_CONTEXT_PATH` to `XGH_CONTEXT_TREE` (and all references throughout)
2. Line 209: Change `"domains": []` to `"entries": []`

- [ ] **Step 2: Update configure.sh**

Rewrite `scripts/configure.sh` to initialize manifest with flat `entries[]` schema. If existing manifest has `domains[]`, migrate entries to flat list.

- [ ] **Step 3: Update commands/query.md and commands/status.md**

Find-and-replace `XGH_CONTEXT_TREE_PATH` → `XGH_CONTEXT_TREE` in both files.

- [ ] **Step 4: Run install + techpack + uninstall tests**

```bash
bash tests/test-install.sh && bash tests/test-techpack.sh && bash tests/test-uninstall.sh
```
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add install.sh scripts/configure.sh commands/query.md commands/status.md
git commit -m "chore: update install/commands for flat manifest and XGH_CONTEXT_TREE env var"
```

---

### Task 10: Integration test + full suite verification

**Files:**
- Create: `tests/test-ct-integration.sh` (overwrite existing)

**Depends on:** All previous tasks

- [ ] **Step 1: Write integration test**

End-to-end test that exercises the full lifecycle:
1. `context-tree.sh init` — verify manifest created
2. Create 4 entries across 2 domains
3. Verify manifest has 4 entries (flat schema)
4. Verify `_index.md` generated per domain
5. Read entry — verify accessCount incremented, importance bumped
6. Update entry — verify updateCount incremented, importance bumped
7. Score entry — verify maturity promotion (draft→validated at 65+)
8. Search — verify results returned and scored
9. Archive — verify low-importance drafts archived, stubs created
10. Restore — verify file restored from archive
11. Delete — verify file removed, archived counterparts cleaned
12. List — verify remaining entries correct

~25 assertions.

- [ ] **Step 2: Run integration test**

```bash
bash tests/test-ct-integration.sh
```

- [ ] **Step 3: Run FULL test suite**

```bash
for t in tests/test-*.sh; do echo -n "$t: "; bash "$t" 2>&1 | tail -1; done
```
Expected: All ~22 test suites pass, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add tests/test-ct-integration.sh
git commit -m "test: rewrite integration test for best-of-both API"
```

- [ ] **Step 5: Final commit — push to remote**

```bash
git push origin feat/initial-release
```

---

## Task Dependency Graph

```
Task 1 (ct-frontmatter) ──┬── Task 2 (ct-scoring) ──┐
                           ├── Task 3 (ct-manifest) ──┼── Task 6 (ct-sync) ── Task 7 (context-tree.sh)
                           └── Task 4 (ct-archive) ──┘                              │
                                                                                      │
Task 5 (ct-search) ──────────────────────────────────── Task 6 (ct-sync) ─────────────┘
                                                                                      │
Task 8 (hooks) ──── independent ──────────────────────────────────────────────────────│
                                                                                      │
Task 9 (light-touch) ── independent ──────────────────────────────────────────────────│
                                                                                      │
Task 10 (integration) ── depends on all ──────────────────────────────────────────────┘
```

**Parallelizable groups:**
- **Wave 1:** Task 1 (ct-frontmatter) — must go first
- **Wave 2:** Tasks 2, 3, 4, 5, 8, 9 — all independent after Task 1
- **Wave 3:** Task 6 (ct-sync) — needs 2, 3, 4, 5
- **Wave 4:** Task 7 (context-tree.sh) — needs 6
- **Wave 5:** Task 10 (integration) — needs all
