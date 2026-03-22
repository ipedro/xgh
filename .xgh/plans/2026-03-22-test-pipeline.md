# Test Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the four-skill pipeline (config → index → architecture → test-builder) that analyzes any project and generates a tailored test suite.

**Architecture:** Four Claude Code plugin skills, each a markdown file in `skills/<name>/<name>.md` with a matching command in `commands/<name>.md`. Skills are prompt-based (no compiled code). They read/write to `~/.xgh/ingest.yaml` and lossless-claude memory via MCP tools.

**Tech Stack:** Claude Code plugin skills (markdown), shell (bash for tests), YAML (ingest.yaml schema)

**Spec:** `.xgh/specs/2026-03-22-test-pipeline-design.md`

**Conventions:**
- Command names use `xgh-` prefix for core skills (e.g., `name: xgh-config`)
- Skills live in `skills/<name>/<name>.md`, commands in `commands/<name>.md`
- All skills that read `ingest.yaml` must resolve the active project by matching cwd git remote against `projects.<name>.github` entries. If no match → stop and prompt `/xgh:config add-project`.

---

### Task 1: Create `/xgh:config` skill and command

**Files:**
- Create: `skills/config/config.md`
- Create: `commands/config.md`

- [ ] **Step 1: Create the command file**

Create `commands/config.md` with frontmatter:
- `name: xgh-config`
- `description: "Structured editor for ~/.xgh/ingest.yaml — show, set, add-project, remove-project, validate"`
- `allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion`
- Body: usage docs for show, set, add-project, remove-project, validate subcommands
- `ARGUMENTS: $ARGUMENTS`

- [ ] **Step 2: Create the skill file**

Create `skills/config/config.md` following the spec's Skill 1 section. Must implement:
- Frontmatter: name `xgh:config`, description, type: flexible, triggers
- Parse `$ARGUMENTS` to determine subcommand
- `show [section]`: read `~/.xgh/ingest.yaml` via python3+PyYAML, pretty-print full manifest or dot-path section
- `set <path> <value>`: dot-path notation (e.g., `projects.xgh.stack shell`), validate value types
- `add-project <name>`: interactive — ask github repo, stack (with types: `shell`, `typescript`, `swift`, `kotlin`, `go`, `rust`, `python`, `generic`), surfaces (types: `cli`, `api`, `web`, `mobile`, `library`, `plugin`, `sdk`), then write
- `remove-project <name>`: confirm via AskUserQuestion then remove
- `validate`: check each project for required fields (`stack`, `surfaces`, `github`), report type mismatches (stack must be string, surfaces must be list of objects with `type` key), report missing fields

- [ ] **Step 3: Run tests to validate registration**

Run: `bash tests/test-config.sh`
Expected: config command and skill detected

- [ ] **Step 4: Commit**

```bash
git add skills/config/config.md commands/config.md
git commit -m "feat: add /xgh:config skill for structured manifest editing"
```

---

### Task 2: Refactor `/xgh:index` skill

**Files:**
- Modify: `skills/index/index.md`
- Modify: `commands/index.md`

- [ ] **Step 1: Read current files**

Read `skills/index/index.md` and `commands/index.md` to understand full content before modifying.

- [ ] **Step 2: Rewrite the index skill**

Replace `skills/index/index.md` with trimmed version per spec. The new skill must:

**Remove entirely:**
- Execution mode preamble (P1-P4, lines 17-78)
- Stack detection from filesystem (lines 88-96)
- All full-mode extra passes: iOS/Swift, Android/Kotlin, TypeScript/React, All stacks (lines 113-138)
- MCP dependency guard check (frontmatter `mcp_dependencies`)
- Quick/full mode distinction

**Keep (simplified):**
- Directory structure: Glob depth 2, map top-level layout
- Key files: read manifests, entry points, README
- Module inventory: list modules, key files per module
- Naming conventions: sample files, extract patterns
- Store to memory: write with tags `["xgh:index", "<repo-name>"]`
- Update `index.last_run` timestamp in `ingest.yaml`

**Add new:**
- Project resolution: match cwd git remote against `projects.<name>.github` in `~/.xgh/ingest.yaml`. If no match → stop, tell user to run `/xgh:config add-project`.
- Read `stack` and `surfaces` from resolved project config. If `stack` or `surfaces` missing → stop, tell user to run `/xgh:config set`.
- Memory format: `[REPO][MODULE] <name>: <purpose>\nKey files: ...\nPattern: ...\nStack: <from ingest.yaml>\nIndexed: <ISO date>`
- Offer architecture at end: "Index complete. Run `/xgh:architecture`? [y/n]"

- [ ] **Step 3: Update the command file**

Update `commands/index.md` description to: "Raw codebase inventory — extracts module list, key files, and naming conventions into lossless-claude memory"

- [ ] **Step 4: Run tests**

Run: `bash tests/test-config.sh`
Expected: index skill/command still detected, structure valid

- [ ] **Step 5: Commit**

```bash
git add skills/index/index.md commands/index.md
git commit -m "refactor: trim /xgh:index to pure codebase inventory"
```

---

### Task 3: Create `/xgh:architecture` skill and command

**Files:**
- Create: `skills/architecture/architecture.md`
- Create: `commands/architecture.md`

- [ ] **Step 1: Create the command file**

Create `commands/architecture.md` with frontmatter:
- `name: xgh-architecture`
- `description: "Analyze codebase architecture — module boundaries, dependency graph, critical paths, public surfaces"`
- `allowed-tools: Bash, Read, Glob, Grep, Agent`
- Body: usage for `[quick|full]` mode argument
- `ARGUMENTS: $ARGUMENTS`

- [ ] **Step 2: Create the skill file**

Create `skills/architecture/architecture.md` per spec's Skill 3 section:

**Frontmatter:** name `xgh:architecture`, description, type: flexible, triggers, mcp_dependencies (lcm_store, lcm_search)

**Project resolution:** Same pattern as index — match cwd git remote against ingest.yaml projects.

**Hard prerequisite — index freshness:**
- Search lossless-claude for `xgh:index:*` entries. If none found → stop, tell user to run `/xgh:index`.
- Read `index.last_run` from project config in `ingest.yaml`.
- If >14 days old → warn: "Index is N days old. Consider re-running `/xgh:index` for fresh results."
- If >60 days old → refuse: "Index is N days old (>60 day limit). Run `/xgh:index` first."

**Parse mode:** default `quick`, accept `full` from arguments.

**Read `stack`** from project config for stack-specific analysis.

**Quick mode produces 3 artifacts:**
- `module-boundaries`: which modules exist, what each owns, seams
- `public-surfaces`: CLI commands, API endpoints, UI routes, exports, SDK methods
- `integration-points`: external systems (DBs, APIs, queues, filesystems)

**Full mode adds 3 more:**
- `dependency-graph`: how modules depend on each other
- `critical-paths`: key user/data journeys
- `test-landscape`: existing coverage, frameworks, gaps

**Stack-specific analysis** (moved from old index full mode):
- iOS/Swift: coordinator pattern, SPM modules, feature flags, DI patterns
- Android/Kotlin: Activity/Fragment hierarchy, Dagger/Hilt, nav graph
- TypeScript/React: component tree, state management, hooks
- All stacks: API routes, service layer, CI/CD config

**Store artifacts** to lossless-claude with tags `["xgh:architecture", "<artifact-name>", "<repo-name>"]`

**Update ingest.yaml:** set `architecture.last_run` (ISO timestamp) and `architecture.mode` (`quick`/`full`)

**Include artifact availability table** in the skill for the LLM's reference.

- [ ] **Step 3: Run tests**

Run: `bash tests/test-config.sh`
Expected: architecture command and skill detected

- [ ] **Step 4: Commit**

```bash
git add skills/architecture/architecture.md commands/architecture.md
git commit -m "feat: add /xgh:architecture skill for codebase analysis"
```

---

### Task 4: Create `/xgh:test-builder` skill — Phase 1 (init)

**Files:**
- Create: `skills/test-builder/test-builder.md`
- Create: `commands/test-builder.md`

- [ ] **Step 1: Create the command file**

Create `commands/test-builder.md` with frontmatter:
- `name: xgh-test-builder`
- `description: "Generate and run tailored test suites from architectural analysis — init to generate, run to execute"`
- `allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion`
- Body: usage for `init` and `run [flow-name]`
- `ARGUMENTS: $ARGUMENTS`

- [ ] **Step 2: Create the skill file with init phase**

Create `skills/test-builder/test-builder.md` with the init phase per spec's Skill 4:

**Frontmatter:** name `xgh:test-builder`, description, type: flexible, triggers, mcp_dependencies (lcm_search)

**Project resolution:** Same pattern as other skills.

**Hard prerequisite — architecture freshness:**
- Search lossless-claude for `xgh:architecture:*` entries. If none → stop, tell user to run `/xgh:architecture`.
- Read `architecture.last_run` from project config in `ingest.yaml`.
- If >7 days → warn: "Architecture analysis is N days old. Consider re-running `/xgh:architecture`."
- If >30 days → refuse: "Architecture analysis is N days old (>30 day limit). Run `/xgh:architecture` first."
- If test-builder detects complex surfaces (multiple surface types, >5 modules) and architecture mode was `quick` → recommend: "Consider running `/xgh:architecture full` for dependency graph and critical paths."

**Parse arguments:** `init` or `run [flow]`. If no argument → show usage.

**Init Step 1 — Read architectural definitions:** Pull module-boundaries, public-surfaces, integration-points (and critical-paths, test-landscape if available) from lossless-claude memory.

**Init Step 2 — Determine project surface type:** Read `surfaces` from ingest.yaml + architecture's `public-surfaces` artifact. Map to test strategy per spec table (CLI→acceptance, API→contract, web→e2e, mobile→e2e, library→contract, mixed→layered).

**Init Step 3 — Complexity gate (adaptive autonomy):** Check these 5 explicit triggers:
1. Multiple surfaces detected
2. No clear entry point
3. Auth/stateful setup required (detected from architecture artifacts)
4. External dependencies that may need mocking (from integration-points)
5. Test landscape shows <30% coverage in critical paths (if available)

If ANY trigger fires → interview developer using AskUserQuestion:
- "What are your critical user journeys?"
- "What breaks frequently vs what's stable?"
- "Which external deps should be mocked vs hit live?"
- "What's your deployment target?"

If NO triggers fire → autonomous generation.

**Init Step 4 — Generate manifest atomically:**
- Write to temp file first: `.xgh/test-builder/manifest.yaml.tmp`
- Validate: check all required fields present, no unresolved placeholders
- Move into place: rename to `.xgh/test-builder/manifest.yaml`
- If init fails mid-generation → delete temp file, no partial manifest left

Include full manifest YAML schema with all fields from spec. Include executor kinds table (shell, http, browser, mobile, library, custom) and assertion types table (exit_code, stdout_contains, stdout_matches, status, body_contains, body_json_path, header_contains, file_exists, returns).

**Init Step 5 — Optional native scaffold:** For known ecosystems, generate test files that implement manifest flows. Manifest remains source of truth.

**Init Step 6 — Generate strategy.md:** Human-readable companion in `.xgh/test-builder/strategy.md` documenting what's being tested and why.

- [ ] **Step 3: Run tests**

Run: `bash tests/test-config.sh`
Expected: test-builder command and skill detected

- [ ] **Step 4: Commit**

```bash
git add skills/test-builder/test-builder.md commands/test-builder.md
git commit -m "feat: add /xgh:test-builder init phase for test suite generation"
```

---

### Task 5: Add `/xgh:test-builder` run phase

**Files:**
- Modify: `skills/test-builder/test-builder.md`

- [ ] **Step 1: Append run phase to the skill file**

Add the run phase after the init section in `skills/test-builder/test-builder.md`:

**Run — argument parsing:**
- No flow name → run all flows
- Flow name provided → run only that flow
- If `.xgh/test-builder/manifest.yaml` missing → stop: "No manifest found. Run `/xgh:test-builder init` first."

**Run — manifest validation on load:**
- Parse YAML, check `version` field exists
- Check for unresolved placeholders (strings containing `TODO`, `???`, `FIXME`)
- Validate schema: each flow has `name`, `surface`, `strategy`, `goal`, `steps`
- If validation fails → refuse to execute, list specific errors

**Run — execute flows:**
For each flow:
1. Run prerequisites (if any), wait for readiness
2. For each step: execute using the declared executor
3. Evaluate assertions against output
4. If executor is unavailable → mark step as `skipped` with explanation (e.g., "Playwright not installed")
5. Run cleanup steps (if any), even on failure
6. Collect results: pass/fail/skip per step

**Run — output format:**
```
## 🧪 test-builder run

| Flow | Surface | Steps | Result | Notes |
|------|---------|-------|--------|-------|
| health-check | api | 1/1 | ✅ | 200ms |
| user-reg | api | 2/2 | ✅ | |
| duplicate | api | 0/1 | ❌ | Expected 409, got 500 |
| browser-flow | web | 0/2 | ⏭️ | Playwright not installed |

4 flows · 3/6 steps passed · 1 failure · 2 skipped
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-config.sh`
Expected: PASS (skill file still valid)

- [ ] **Step 3: Commit**

```bash
git add skills/test-builder/test-builder.md
git commit -m "feat: add /xgh:test-builder run phase with executor dispatch"
```

---

### Task 6: Add tests and skill-triggering prompts

**Files:**
- Modify: `tests/test-config.sh`
- Create: `tests/skill-triggering/prompts/config.txt`
- Create: `tests/skill-triggering/prompts/config-2.txt`
- Create: `tests/skill-triggering/prompts/config-3.txt`
- Create: `tests/skill-triggering/prompts/architecture.txt`
- Create: `tests/skill-triggering/prompts/architecture-2.txt`
- Create: `tests/skill-triggering/prompts/architecture-3.txt`
- Create: `tests/skill-triggering/prompts/test-builder.txt`
- Create: `tests/skill-triggering/prompts/test-builder-2.txt`
- Create: `tests/skill-triggering/prompts/test-builder-3.txt`

- [ ] **Step 1: Read existing test-config.sh**

Read `tests/test-config.sh` to understand the assertion patterns and how it checks for skills/commands.

- [ ] **Step 2: Add structural checks for new skills and commands**

Add checks to `tests/test-config.sh` for:
- `skills/config/config.md` exists and has valid frontmatter
- `commands/config.md` exists and has `name: xgh-config`
- `skills/architecture/architecture.md` exists and has valid frontmatter
- `commands/architecture.md` exists and has `name: xgh-architecture`
- `skills/test-builder/test-builder.md` exists and has valid frontmatter
- `commands/test-builder.md` exists and has `name: xgh-test-builder`

- [ ] **Step 3: Create skill-triggering prompts**

Create 9 natural-language prompt files that should trigger each skill:

config:
- `config.txt`: "show me the current xgh config"
- `config-2.txt`: "add a new project to xgh tracking"
- `config-3.txt`: "set the stack for this project to typescript"

architecture:
- `architecture.txt`: "analyze the architecture of this codebase"
- `architecture-2.txt`: "run a full architectural analysis"
- `architecture-3.txt`: "what are the module boundaries in this project"

test-builder:
- `test-builder.txt`: "generate tests for this project"
- `test-builder-2.txt`: "run the test suite"
- `test-builder-3.txt`: "build an acceptance test plan for this API"

- [ ] **Step 4: Run all tests**

Run: `bash tests/test-config.sh`
Expected: all checks pass including new ones

- [ ] **Step 5: Commit**

```bash
git add tests/test-config.sh tests/skill-triggering/prompts/
git commit -m "test: add structural checks and trigger prompts for pipeline skills"
```
