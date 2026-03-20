# Dynamic Provider Generation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace static provider specs with dynamic generation — Claude reads tool docs at setup time, all providers persist in `~/.xgh/user_providers/`.

**Architecture:** `retrieve-all.sh` scans `~/.xgh/user_providers/` and exports env vars per the fetch.sh contract. `/xgh-track` auto-detects tools and generates providers. `/xgh-retrieve` reads MCP provider.yaml configs generically. Old `providers/*.spec.md` files are deleted.

**Tech Stack:** Bash (retrieve-all.sh, fetch.sh contract), Markdown skills, Python (YAML parsing in retrieve-all.sh)

**Spec:** `.xgh/specs/2026-03-20-dynamic-provider-generation.md`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Modify | `scripts/retrieve-all.sh` | Scan `user_providers/`, export env vars, handle `cli`+`api` modes |
| Create | `tests/test-provider-contract.sh` | Contract tests for fetch.sh interface |
| Modify | `tests/test-retrieve-all.sh` | Update assertions for new path + env vars |
| Modify | `skills/track/track.md` | Auto-detection, doc-reading generation, `user_providers/` path |
| Modify | `skills/retrieve/retrieve.md` | Generic MCP provider dispatch from provider.yaml |
| Modify | `skills/doctor/doctor.md` | Provider health checks for `user_providers/` |
| Modify | `skills/init/init.md` | Persistence guarantee, legacy migration offer |
| Delete | `providers/github/spec.md` | Replaced by dynamic generation |
| Delete | `providers/slack/spec.md` | Replaced by dynamic generation |
| Delete | `providers/jira/spec.md` | Replaced by dynamic generation |
| Delete | `providers/confluence/spec.md` | Replaced by dynamic generation |
| Delete | `providers/figma/spec.md` | Replaced by dynamic generation |
| Delete | `providers/_template/spec.md` | Replaced by dynamic generation |
| Modify | `AGENTS.md` | Document `user_providers/`, persistence contract, mode rename |
| Modify | `README.md` | Update provider architecture description |
| Modify | `tests/test-config.sh` | Remove provider spec existence checks if any |
| Modify | `hooks/session-start.sh` | Update provider path from `providers/` to `user_providers/` |
| Modify | `tests/test-providers.sh` | Rewrite: remove spec existence checks, add user_providers assertions |
| Modify | `tests/test-hooks.sh` | Update fake provider paths to `user_providers/` |
| Modify | `tests/test-pipeline-skills.sh` | Update provider-related assertions |

---

### Task 1: Update retrieve-all.sh — scan user_providers + export env vars

**Files:**
- Modify: `scripts/retrieve-all.sh`
- Modify: `tests/test-retrieve-all.sh`

**Context:** The current script scans `~/.xgh/providers/` and checks `mode: mcp` vs `mode: bash`. It runs `bash "$script"` with no env vars. The new version must:
1. Default to `~/.xgh/user_providers/` (env override via `XGH_PROVIDERS_DIR`)
2. Skip `mode: mcp` providers, run `mode: cli` and `mode: api`
3. Export `PROVIDER_DIR`, `CURSOR_FILE`, `INBOX_DIR`, `TOKENS_FILE` before each `fetch.sh`

- [ ] **Step 1: Update test assertions for new behavior**

Add these assertions to `tests/test-retrieve-all.sh`:

```bash
assert_contains "scripts/retrieve-all.sh" "user_providers"
assert_contains "scripts/retrieve-all.sh" "PROVIDER_DIR"
assert_contains "scripts/retrieve-all.sh" "CURSOR_FILE"
assert_contains "scripts/retrieve-all.sh" "TOKENS_FILE"
assert_contains "scripts/retrieve-all.sh" "mode: cli"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-retrieve-all.sh`
Expected: 5 new FAILs (user_providers, PROVIDER_DIR, CURSOR_FILE, TOKENS_FILE, mode: cli)

- [ ] **Step 3: Update retrieve-all.sh**

In `scripts/retrieve-all.sh`, make these changes:

**Line 5 (comment):** Change `~/.xgh/providers/` to `~/.xgh/user_providers/`
**Line 6:** Change `mode:bash` to `mode:cli and mode:api`

**Line 9 (PROVIDERS_DIR):** Change default:
```bash
PROVIDERS_DIR="${XGH_PROVIDERS_DIR:-$HOME/.xgh/user_providers}"
```

**Line 67 (mode check):** Replace the MCP skip check:
```bash
    # Only run cli and api mode providers (mcp handled by CronCreate prompt)
    local mode
    mode=$(grep "^mode:" "$provider_dir/provider.yaml" 2>/dev/null | awk '{print $2}')
    if [ "$mode" != "cli" ] && [ "$mode" != "api" ]; then
        continue
    fi
```

**Lines 83-85 (fetch.sh invocation):** Export env vars before running:
```bash
    # Export contract env vars for fetch.sh
    export PROVIDER_DIR="$provider_dir"
    export CURSOR_FILE="$provider_dir/cursor"
    export INBOX_DIR  # promote script-level var to env for fetch.sh subprocess
    export TOKENS_FILE="$HOME/.xgh/tokens.env"

    rc=0
    run_with_timeout 30 bash "$script" 2>>"$HOME/.xgh/logs/provider-$name.log" || rc=$?
```

Also handle exit code 2 (partial failure) as a warning, not full failure:
```bash
    if [ "$rc" -eq 0 ]; then
        success=$((success + 1))
    elif [ "$rc" -eq 2 ]; then
        success=$((success + 1))
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: WARN $name — partial failure (exit 2)" >> "$LOG_FILE"
    else
        failed=$((failed + 1))
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) retriever: ERROR $name — exit code $rc" >> "$LOG_FILE"
    fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-retrieve-all.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add scripts/retrieve-all.sh tests/test-retrieve-all.sh
git commit -m "feat(retrieve-all): scan user_providers + export fetch.sh contract env vars"
```

---

### Task 2: Create provider contract test

**Files:**
- Create: `tests/test-provider-contract.sh`

**Context:** This test creates a mock provider in a temp dir, runs retrieve-all.sh against it, and verifies the contract is followed (env vars set, exit codes handled, logging works).

- [ ] **Step 1: Write the contract test**

Create `tests/test-provider-contract.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
assert_equals() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1'"; FAIL=$((FAIL+1)); fi; }
assert_contains() { if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2'"; FAIL=$((FAIL+1)); fi; }
assert_file_exists() { if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 does not exist"; FAIL=$((FAIL+1)); fi; }

# Setup temp environment
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PROVIDERS="$TMPDIR/user_providers"
INBOX="$TMPDIR/.xgh/inbox"
LOGS="$TMPDIR/.xgh/logs"
mkdir -p "$PROVIDERS/test-cli" "$INBOX" "$LOGS"

# Create a mock provider.yaml
cat > "$PROVIDERS/test-cli/provider.yaml" << 'YAML'
service: test
mode: cli
cursor_strategy: iso8601
YAML

# Create a mock fetch.sh that validates contract env vars
cat > "$PROVIDERS/test-cli/fetch.sh" << 'FETCH'
#!/usr/bin/env bash
# Validate env vars are set
[ -n "$PROVIDER_DIR" ] || { echo "PROVIDER_DIR not set" >&2; exit 1; }
[ -n "$CURSOR_FILE" ] || { echo "CURSOR_FILE not set" >&2; exit 1; }
[ -n "$INBOX_DIR" ] || { echo "INBOX_DIR not set" >&2; exit 1; }
[ -n "$TOKENS_FILE" ] || { echo "TOKENS_FILE not set" >&2; exit 1; }

# Write a test inbox item
cat > "$INBOX_DIR/2026-03-20T00-00-00Z_test_item_test_1.md" << 'ITEM'
---
type: test_item
source_type: test_item
source: test
project: test-project
timestamp: 2026-03-20T00:00:00Z
urgency_score: 0
processed: false
tags: []
---
Test item content
ITEM

# Write cursor
echo "2026-03-20T00:00:00Z" > "$CURSOR_FILE"

echo "fetched=1"
exit 0
FETCH
chmod +x "$PROVIDERS/test-cli/fetch.sh"

# Run retrieve-all.sh against mock environment
export XGH_PROVIDERS_DIR="$PROVIDERS"
export HOME="$TMPDIR"
mkdir -p "$TMPDIR/.xgh/logs" "$TMPDIR/.xgh/inbox"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$REPO_ROOT/scripts/retrieve-all.sh" 2>/dev/null

# Verify contract
assert_file_exists "$INBOX/2026-03-20T00-00-00Z_test_item_test_1.md"
assert_file_exists "$PROVIDERS/test-cli/cursor"
assert_contains "$PROVIDERS/test-cli/cursor" "2026-03-20T00:00:00Z"
assert_contains "$LOGS/retriever.log" "1 providers"
assert_contains "$LOGS/retriever.log" "1 ok"

# Test exit code 2 (partial failure)
cat > "$PROVIDERS/test-cli/fetch.sh" << 'FETCH2'
#!/usr/bin/env bash
echo "fetched=0"
exit 2
FETCH2
chmod +x "$PROVIDERS/test-cli/fetch.sh"

bash "$REPO_ROOT/scripts/retrieve-all.sh" 2>/dev/null
assert_contains "$TMPDIR/.xgh/logs/retriever.log" "WARN test-cli"

# Test MCP provider is skipped
mkdir -p "$PROVIDERS/test-mcp"
cat > "$PROVIDERS/test-mcp/provider.yaml" << 'YAML'
service: test-mcp
mode: mcp
mcp_server: test
YAML
# No fetch.sh — should be skipped without error

bash "$REPO_ROOT/scripts/retrieve-all.sh" 2>/dev/null
# Should still show 1 provider (mcp skipped)
assert_contains "$TMPDIR/.xgh/logs/retriever.log" "1 providers"

echo ""; echo "Provider contract: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run the contract test**

Run: `bash tests/test-provider-contract.sh`
Expected: All pass (retrieve-all.sh from Task 1 already exports env vars)

- [ ] **Step 3: Commit**

```bash
git add tests/test-provider-contract.sh
git commit -m "test: add provider contract test for fetch.sh interface"
```

---

### Task 2b: Update session-start hook + provider/hook tests

**Files:**
- Modify: `hooks/session-start.sh`
- Modify: `tests/test-providers.sh`
- Modify: `tests/test-hooks.sh`

**Context:** The session-start hook hardcodes `~/.xgh/providers/` in three places for provider detection and scheduler CronCreate instructions. The test-providers.sh file asserts that `providers/*/spec.md` files exist. The test-hooks.sh file creates fake providers under `~/.xgh/providers/`. All need updating.

- [ ] **Step 1: Read and update session-start hook**

Read `hooks/session-start.sh`. Find all references to `~/.xgh/providers/` and replace with `~/.xgh/user_providers/`. Also update `mode: bash` references to `mode: cli`.

- [ ] **Step 2: Read and rewrite test-providers.sh**

Read `tests/test-providers.sh`. Remove all assertions that check for `providers/*/spec.md` files (these are being deleted). Replace with assertions that validate:
- `scripts/retrieve-all.sh` references `user_providers`
- `skills/track/track.md` references `user_providers`
- `skills/doctor/doctor.md` references `user_providers`

- [ ] **Step 3: Update test-hooks.sh**

Read `tests/test-hooks.sh`. Find lines that create fake providers under `~/.xgh/providers/` and update to `~/.xgh/user_providers/`. Update any `mode: bash` to `mode: cli`.

- [ ] **Step 4: Run tests**

Run: `bash tests/test-providers.sh && bash tests/test-hooks.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start.sh tests/test-providers.sh tests/test-hooks.sh
git commit -m "feat: update session-start hook + tests for user_providers path"
```

---

### Task 3: Update track skill for dynamic provider generation

**Files:**
- Modify: `skills/track/track.md`

**Context:** The track skill currently has a "Step 3b: Generate provider scripts" section that reads static `providers/*/spec.md` files from the plugin cache. Replace this entire section with the dynamic generation flow: auto-detect → read docs → generate → validate → save to `~/.xgh/user_providers/`.

Read `skills/track/track.md` first. Then replace Step 3b with the new flow. Keep all other steps intact.

The new Step 3b should contain:

1. **Auto-detection** — For each service the user wants to track (GitHub, Slack, etc.), probe the system:
   - GitHub: `command -v gh && gh auth status`
   - Slack: Check session tool list for `slack_` tools, or check `tokens.env` for `SLACK_BOT_TOKEN`
   - Jira/Confluence: Check session tool list for `atlassian` tools
   - Figma: Check session tool list for `figma` tools
   - Generic: Ask "CLI binary, OpenAPI endpoint, or MCP server?"

2. **Doc reading** — Based on detected mode:
   - CLI: Run `<binary> --help` and targeted subcommand help. Parse available commands, flags, output formats.
   - API: Fetch the OpenAPI spec URL. Identify GET collection endpoints with date filters.
   - MCP: List available tools from the MCP server. Identify read/list/search tools.

3. **Generation** — Generate `provider.yaml` + `fetch.sh` (for cli/api) or `provider.yaml` only (for mcp):
   - Directory: `~/.xgh/user_providers/<service>-<mode>/`
   - Follow the provider.yaml schema from the spec
   - Follow the fetch.sh contract from the spec (reads CURSOR_FILE, INBOX_DIR, PROVIDER_DIR, TOKENS_FILE)
   - Populate repos/endpoints from the project's `ingest.yaml` config

4. **Validation** — Run the generated `fetch.sh` with cursor set to now:
   ```bash
   CURSOR_FILE="<dir>/cursor" INBOX_DIR="$HOME/.xgh/inbox" PROVIDER_DIR="<dir>" TOKENS_FILE="$HOME/.xgh/tokens.env" bash "<dir>/fetch.sh"
   ```
   Confirm exit 0. Report results. If validation fails, show the error and offer to retry or skip.

5. **Conflict handling** — If a provider for this service already exists, warn:
   ```
   You already have a GitHub provider (github-cli).
   Replace it? Or rename the existing one to keep both? [Replace/Rename/Skip]
   ```

6. **Persistence note** — Add a comment at the top of Step 3b:
   ```
   Provider scripts are saved to ~/.xgh/user_providers/ which is NEVER
   touched by plugin installs or /xgh-init. Only /xgh-track creates or
   modifies provider files, and only with user confirmation.
   ```

Also update any references to `~/.xgh/providers/` → `~/.xgh/user_providers/` throughout the skill.
Also update references to `mode: bash` → `mode: cli` (or `mode: api` for API providers).
Remove any references to reading `providers/*/spec.md` from the plugin cache.

- [ ] **Step 1: Read the current track skill**

Read: `skills/track/track.md`

- [ ] **Step 2: Replace Step 3b with dynamic generation flow**

Replace the entire "Step 3b" section (provider script generation) with the new auto-detect → read docs → generate → validate → save flow as described above.

- [ ] **Step 3: Update all path references in the skill**

Find and replace:
- `~/.xgh/providers/` → `~/.xgh/user_providers/`
- `mode: bash` → `mode: cli` (in provider.yaml context)
- Remove references to reading spec files from plugin cache

- [ ] **Step 4: Add regeneration support**

At the end of the track skill, add a section:

```markdown
## Regeneration

When invoked as `/xgh-track --regenerate <provider-name>`:

1. Read existing `~/.xgh/user_providers/<provider-name>/provider.yaml` for current config
2. Re-read tool documentation (--help, OpenAPI spec, MCP tool list)
3. Generate new `fetch.sh` (or update `provider.yaml`)
4. Validate with a test fetch
5. Replace old script only after validation passes
6. Report: "Regenerated <provider-name>. Config preserved, script updated."
```

- [ ] **Step 5: Run tests**

Run: `bash tests/test-pipeline-skills.sh`
Expected: Existing assertions still pass

- [ ] **Step 6: Commit**

```bash
git add skills/track/track.md
git commit -m "feat(track): dynamic provider generation with auto-detection"
```

---

### Task 4: Update retrieve skill for generic MCP provider dispatch

**Files:**
- Modify: `skills/retrieve/retrieve.md`

**Context:** The retrieve skill currently has hardcoded Slack MCP tool calls. Add a new step that scans `~/.xgh/user_providers/` for `mode: mcp` providers, reads their `provider.yaml`, and calls the declared MCP tools generically.

Read `skills/retrieve/retrieve.md` first. Find the section that handles MCP providers (the CronCreate prompt lane). Replace hardcoded tool calls with a generic dispatch loop.

The new MCP dispatch section should:

1. Scan `~/.xgh/user_providers/` for directories with `mode: mcp` in `provider.yaml`
2. For each MCP provider, read the `tools:` section from `provider.yaml`
3. Call each declared tool with cursor-based parameters
4. Write inbox items in the standard frontmatter format
5. Advance the provider's cursor file

Also update all references to `~/.xgh/providers/` → `~/.xgh/user_providers/`.

- [ ] **Step 1: Read the current retrieve skill**

Read: `skills/retrieve/retrieve.md`

- [ ] **Step 2: Add generic MCP provider dispatch**

After the existing Slack channel scanning section, add a new section:

```markdown
## Step N — MCP Provider Dispatch

For each provider in `~/.xgh/user_providers/` with `mode: mcp`:

1. Read `provider.yaml` to get the `tools:` section and `cursor_strategy`
2. Read the cursor file (`~/.xgh/user_providers/<name>/cursor`)
3. For each tool declared in `tools:`:
   - Substitute `{cursor}` in params with the current cursor value
   - Call the MCP tool
   - Parse results into inbox items (standard frontmatter format)
   - Write to `~/.xgh/inbox/`
4. Update the cursor file with the timestamp of the most recent item
```

- [ ] **Step 3: Update path references**

Find and replace `~/.xgh/providers/` → `~/.xgh/user_providers/` throughout the skill.

- [ ] **Step 4: Commit**

```bash
git add skills/retrieve/retrieve.md
git commit -m "feat(retrieve): generic MCP provider dispatch from provider.yaml"
```

---

### Task 5: Update doctor skill for user_providers

**Files:**
- Modify: `skills/doctor/doctor.md`
- Modify: `tests/test-pipeline-skills.sh`

**Context:** The doctor skill has "Check 6 — Providers" that lists directories in `~/.xgh/providers/`. Update to scan `~/.xgh/user_providers/` and check for `mode: cli`/`mode: api`/`mode: mcp` instead of `mode: bash`.

Read `skills/doctor/doctor.md` first. Find Check 6 and update:

1. Path: `~/.xgh/providers/` → `~/.xgh/user_providers/`
2. Mode checks: `mode: bash` → `mode: cli` or `mode: api`
3. Add legacy detection: if `~/.xgh/providers/` exists with content, suggest migration
4. Update example output to use `<service>-<mode>` naming

- [ ] **Step 1: Read the current doctor skill**

Read: `skills/doctor/doctor.md`

- [ ] **Step 2: Update Check 6 — Providers**

Replace Check 6 path references and mode checks. Update the example output:

```
Providers
  ✓ github-cli: 3 repos, cli mode, cursor 4 min ago
  ✓ slack-mcp: 2 channels, mcp mode (OAuth), cursor 4 min ago
  ✗ figma-api: fetch.sh missing — run /xgh-track --regenerate figma-api
  ⚠ jira-mcp: mcp mode, cursor 3 hours ago (stale — check MCP server)
```

Add legacy detection after provider listing:
```markdown
If `~/.xgh/providers/` exists with non-empty subdirectories:
```
⚠ Legacy providers found in ~/.xgh/providers/
  Run /xgh-track to migrate to ~/.xgh/user_providers/
```
```

- [ ] **Step 3: Update test assertions**

In `tests/test-pipeline-skills.sh`, update any assertions that reference `~/.xgh/providers/` to `~/.xgh/user_providers/` and `mode: bash` to `mode: cli`.

- [ ] **Step 4: Run tests**

Run: `bash tests/test-pipeline-skills.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add skills/doctor/doctor.md tests/test-pipeline-skills.sh
git commit -m "feat(doctor): update provider checks for user_providers + mode:cli"
```

---

### Task 6: Update init skill — persistence guarantee + migration

**Files:**
- Modify: `skills/init/init.md`

**Context:** The init skill creates data directories and installs scripts. It must:
1. Create `~/.xgh/user_providers/` in the bootstrap step
2. Add a comment that init NEVER modifies existing user_providers content
3. Detect legacy `~/.xgh/providers/` and offer migration
4. Remove the step that copies retrieve-all.sh (it now reads from user_providers directly from the repo)

Read `skills/init/init.md` first. Find the bootstrap step (Step 0a) and update.

- [ ] **Step 1: Read the current init skill**

Read: `skills/init/init.md`

- [ ] **Step 2: Update Step 0a — add user_providers to mkdir**

In the `mkdir -p` command, add `~/.xgh/user_providers`:
```bash
mkdir -p ~/.xgh/inbox/processed ~/.xgh/logs ~/.xgh/digests ~/.xgh/calibration ~/.xgh/user_providers
```

- [ ] **Step 3: Add persistence guarantee comment**

After the mkdir, add:
```markdown
> **Persistence guarantee:** `~/.xgh/user_providers/` is user-owned. `/xgh-init` creates
> the directory but NEVER deletes, overwrites, or modifies its contents. Only `/xgh-track`
> touches provider files, and only with user confirmation.
```

- [ ] **Step 4: Add legacy migration detection**

After Step 0b (Stale Install Cleanup), add:

```markdown
### 0c. Legacy Provider Migration

```bash
if [ -d ~/.xgh/providers ] && [ "$(ls -A ~/.xgh/providers 2>/dev/null)" ]; then
    echo "Found legacy providers in ~/.xgh/providers/"
    ls ~/.xgh/providers/
fi
```

If legacy providers found, offer migration:
```
Legacy providers detected. Migrate to ~/.xgh/user_providers/?
This renames directories to <service>-<mode> format. [Y/n]
```

If yes: for each provider dir, read mode from provider.yaml, rename to `<service>-<mode>`, move to `~/.xgh/user_providers/`. Rewrite `mode: bash` to `mode: cli`.

If no: continue. Doctor will remind them later.
```

- [ ] **Step 5: Commit**

```bash
git add skills/init/init.md
git commit -m "feat(init): add user_providers dir + legacy migration"
```

---

### Task 7: Delete old provider specs

**Files:**
- Delete: `providers/github/spec.md`
- Delete: `providers/slack/spec.md`
- Delete: `providers/jira/spec.md`
- Delete: `providers/confluence/spec.md`
- Delete: `providers/figma/spec.md`
- Delete: `providers/_template/spec.md`

**Context:** These are replaced by dynamic generation. Check if there are any test assertions referencing these files first. Also check if the `providers/` directory has any other content that should stay.

- [ ] **Step 1: Check for test references to provider specs**

Search for `spec.md` in `tests/` to find assertions that check for provider spec files. Remove those assertions.

Also search for `providers/` references in test files — update or remove as needed.

- [ ] **Step 2: Check providers/ directory for non-spec content**

List `providers/` directory. If there's nothing besides specs and `_template/`, delete the entire directory. If there's other content, keep the directory and only delete spec files.

- [ ] **Step 3: Delete spec files**

```bash
rm -f providers/github/spec.md providers/slack/spec.md providers/jira/spec.md \
     providers/confluence/spec.md providers/figma/spec.md providers/_template/spec.md
# Remove empty directories
rmdir providers/github providers/slack providers/jira providers/confluence \
      providers/figma providers/_template 2>/dev/null || true
# Remove providers/ if empty
rmdir providers 2>/dev/null || true
```

- [ ] **Step 4: Run full test suite**

Run: `for t in tests/test-*.sh; do echo -n "$(basename $t): "; bash "$t" 2>&1 | tail -1; done`
Expected: No new failures from spec deletion

- [ ] **Step 5: Commit**

```bash
git add -A providers/
git commit -m "chore: remove static provider specs (replaced by dynamic generation)"
```

---

### Task 8: Update AGENTS.md and README.md

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`

**Context:** Both files reference the provider architecture. Update to reflect:
- `~/.xgh/user_providers/` instead of `~/.xgh/providers/`
- Dynamic generation instead of static specs
- `mode: cli`/`mode: api`/`mode: mcp` instead of `mode: bash`/`mode: mcp`
- Persistence guarantee
- Auto-detection capability

Read both files first. Make targeted edits — don't rewrite entire sections unless necessary.

- [ ] **Step 1: Read AGENTS.md and find provider-related sections**

Read: `AGENTS.md`

Search for: "provider", "spec.md", "mode: bash", "~/.xgh/providers"

- [ ] **Step 2: Update AGENTS.md**

Key changes:
- File structure listing: `providers/` → show `providers/` as deleted, add `~/.xgh/user_providers/` description
- Provider framework description: update to describe dynamic generation
- Mode terminology: `bash` → `cli`/`api`
- Add persistence guarantee to relevant section
- Remove any "Adding a new provider" subsection that references spec files

- [ ] **Step 3: Read README.md and find provider-related sections**

Read: `README.md`

Search for: "provider", "spec.md", "mode: bash"

- [ ] **Step 4: Update README.md**

Key changes:
- Architecture description: update provider model to dynamic generation
- Remove references to `providers/*/spec.md` files
- Update any file tree listings

- [ ] **Step 5: Run tests**

Run: `bash tests/test-pipeline-skills.sh && bash tests/test-config.sh`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md README.md
git commit -m "docs: update provider architecture for dynamic generation"
```

---

### Task 9: Create example provider configs

**Files:**
- Create: `providers/examples/github-cli.yaml`
- Create: `providers/examples/slack-mcp.yaml`
- Create: `providers/examples/linear-api.yaml`
- Create: `providers/examples/README.md`

**Context:** With static specs retired, users need reference examples showing what generated `provider.yaml` files look like for each mode. These are documentation-only — not consumed by any script.

- [ ] **Step 1: Create github-cli example**

Create `providers/examples/github-cli.yaml` showing a complete CLI-mode provider config with per-repo sources, watch_prs with search queries, and cursor strategy.

- [ ] **Step 2: Create slack-mcp example**

Create `providers/examples/slack-mcp.yaml` showing an MCP-mode provider with tools (channels, threads, search), cursor strategy, and tool role conventions.

- [ ] **Step 3: Create linear-api example**

Create `providers/examples/linear-api.yaml` showing an API-mode provider with OpenAPI endpoint config, auth, pagination, and item mapping.

- [ ] **Step 4: Create README**

Create `providers/examples/README.md` explaining:
- These are reference examples of what `/xgh-track` generates
- Users should NOT copy these manually — run `/xgh-track` instead
- The three modes (cli, api, mcp) and when each applies
- Where generated configs live (`~/.xgh/user_providers/`)

- [ ] **Step 5: Commit**

```bash
git add providers/examples/
git commit -m "docs: add example provider configs for cli/mcp/api modes"
```

---

### Task 10: Final test suite + cleanup

(formerly Task 9)

**Files:**
- All test files

**Context:** Run the full test suite and fix any remaining failures introduced by this work. Do NOT fix pre-existing failures (test-brief.sh XGH_BRIEFING, test-multi-agent.sh agent-collaboration, test-plan4-integration.sh cross-references).

- [ ] **Step 1: Run full test suite**

Run: `for t in tests/test-*.sh; do echo -n "$(basename $t): "; bash "$t" 2>&1 | tail -1; done`

- [ ] **Step 2: Fix any new failures**

Compare against known pre-existing failures:
- `test-brief.sh`: 1 fail (XGH_BRIEFING) — pre-existing
- `test-briefing.sh`: 1 fail (XGH_BRIEFING) — pre-existing
- `test-multi-agent.sh`: 2 fails (agent-collaboration) — pre-existing
- `test-plan4-integration.sh`: 3 fails (cross-references) — pre-existing

Any failures NOT in this list were introduced by this work and must be fixed.

- [ ] **Step 3: Verify retrieve-all.sh contract test passes**

Run: `bash tests/test-provider-contract.sh`
Expected: All pass

- [ ] **Step 4: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix: resolve test failures from provider migration"
```
