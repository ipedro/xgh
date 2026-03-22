# Test Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the four-skill pipeline (config → index → architecture → test-builder) that analyzes any project and generates a tailored test suite.

**Architecture:** Four Claude Code plugin skills, each a markdown file in `skills/<name>/<name>.md` with a matching command in `commands/<name>.md`. Skills are prompt-based (no compiled code). They read/write to `~/.xgh/ingest.yaml` and lossless-claude memory via MCP tools.

**Tech Stack:** Claude Code plugin skills (markdown), shell (bash for tests), YAML (ingest.yaml schema)

**Spec:** `.xgh/specs/2026-03-22-test-pipeline-design.md`

---

### Task 1: Create `/xgh:config` skill

**Files:**
- Create: `skills/config/config.md`
- Create: `commands/config.md`

- [ ] **Step 1: Create the command file**

`commands/config.md`:
```markdown
---
name: config
description: "Structured editor for ~/.xgh/ingest.yaml — show, set, add-project, remove-project, validate"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# /xgh-config

Run the `xgh:config` skill to read or modify the xgh project manifest.

## Usage

\```
/xgh-config show [section]
/xgh-config set <dot.path> <value>
/xgh-config add-project <name>
/xgh-config remove-project <name>
/xgh-config validate
\```

ARGUMENTS: $ARGUMENTS
```

- [ ] **Step 2: Create the skill file**

Create `skills/config/config.md` following the spec's Skill 1 section. The skill must:
- Parse `$ARGUMENTS` to determine subcommand (show, set, add-project, remove-project, validate)
- Read `~/.xgh/ingest.yaml` using python3+PyYAML for all operations
- `show`: pretty-print full manifest or a dot-path section
- `set`: use dot-path notation to set values (e.g., `projects.xgh.stack shell`)
- `add-project`: interactive — ask name, github repo, stack, surfaces, then write
- `remove-project`: confirm then remove the project entry
- `validate`: check for required fields (stack, surfaces, github) in each project
- Include the new schema fields: `stack` and `surfaces` per project
- Reference the spec for the full schema

- [ ] **Step 3: Validate command registration**

Run: `bash tests/test-config.sh`
Expected: config command and skill are detected

- [ ] **Step 4: Commit**

```bash
git add skills/config/config.md commands/config.md
git commit -m "feat: add /xgh:config skill for structured manifest editing"
```

---

### Task 2: Refactor `/xgh:index` skill

**Files:**
- Modify: `skills/index/index.md`

- [ ] **Step 1: Read the current index skill**

Read `skills/index/index.md` to understand the full current content before modifying.

- [ ] **Step 2: Rewrite the index skill**

Replace the entire content of `skills/index/index.md` with the trimmed version per spec:
- Remove: execution mode preamble (P1-P4), stack detection from filesystem, all full-mode extra passes, MCP dependency guard, quick/full distinction
- Keep: directory structure scan, key files, module inventory, naming conventions, store to memory, update timestamps
- Add: read `stack` and `surfaces` from `ingest.yaml` (via python3+PyYAML), hard prerequisite check
- Add: offer to run `/xgh:architecture` at the end
- Update frontmatter description to match new purpose
- Memory format: `[REPO][MODULE]` with tags `["xgh:index", "<repo-name>"]`

- [ ] **Step 3: Update the command file if needed**

Read `commands/index.md` and update the description/usage to reflect the simplified skill.

- [ ] **Step 4: Run existing tests**

Run: `bash tests/test-config.sh`
Expected: index skill/command still detected, structure valid

- [ ] **Step 5: Commit**

```bash
git add skills/index/index.md commands/index.md
git commit -m "refactor: trim /xgh:index to pure codebase inventory"
```

---

### Task 3: Create `/xgh:architecture` skill

**Files:**
- Create: `skills/architecture/architecture.md`
- Create: `commands/architecture.md`

- [ ] **Step 1: Create the command file**

`commands/architecture.md`:
```markdown
---
name: architecture
description: "Analyze codebase architecture — module boundaries, dependency graph, critical paths, public surfaces"
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# /xgh-architecture

Run the `xgh:architecture` skill to produce architectural definitions from the codebase index.

## Usage

\```
/xgh-architecture [quick|full]
\```

ARGUMENTS: $ARGUMENTS
```

- [ ] **Step 2: Create the skill file**

Create `skills/architecture/architecture.md` per spec's Skill 3 section:
- Frontmatter: name, description, type: flexible, triggers, mcp_dependencies (lcm_store, lcm_search)
- Hard prerequisite: check for `xgh:index:*` entries in lossless-claude memory
- Parse mode from arguments (default: quick)
- Read `stack` from `ingest.yaml` for stack-specific analysis
- Quick mode artifacts: module-boundaries, public-surfaces, integration-points
- Full mode: add dependency-graph, critical-paths, test-landscape
- Stack-specific analysis passes (iOS/Swift, Android/Kotlin, TypeScript/React, All stacks) — moved from old index full mode
- Store each artifact to lossless-claude with `xgh:architecture:` prefix tags
- Update `architecture.last_run` and `architecture.mode` in `ingest.yaml`
- Artifact availability table in the skill for reference

- [ ] **Step 3: Run tests**

Run: `bash tests/test-config.sh`
Expected: architecture command and skill detected

- [ ] **Step 4: Commit**

```bash
git add skills/architecture/architecture.md commands/architecture.md
git commit -m "feat: add /xgh:architecture skill for codebase analysis"
```

---

### Task 4: Create `/xgh:test-builder` skill

**Files:**
- Create: `skills/test-builder/test-builder.md`
- Create: `commands/test-builder.md`

- [ ] **Step 1: Create the command file**

`commands/test-builder.md`:
```markdown
---
name: test-builder
description: "Generate and run tailored test suites from architectural analysis — init to generate, run to execute"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
---

# /xgh-test-builder

Run the `xgh:test-builder` skill to generate or execute a test suite.

## Usage

\```
/xgh-test-builder init
/xgh-test-builder run [flow-name]
\```

ARGUMENTS: $ARGUMENTS
```

- [ ] **Step 2: Create the skill file — Phase 1 (init)**

Create `skills/test-builder/test-builder.md` per spec's Skill 4 section. The init phase must:
- Hard prerequisite: check for `xgh:architecture:*` entries, freshness check (warn >7d, refuse >30d)
- Read timestamps from `ingest.yaml` project config
- Step 1: Read architectural definitions from lossless-claude memory
- Step 2: Determine project surface type from `surfaces` in ingest.yaml + architecture artifacts
- Step 3: Complexity gate — list the 5 explicit triggers for interview mode
- Step 4: Generate manifest atomically (temp file → validate → move)
- Include the full manifest YAML schema with all fields documented
- Include executor kinds table and assertion types table from spec
- Step 5: Optional native scaffold
- Step 6: Generate strategy.md companion

- [ ] **Step 3: Add Phase 2 (run) to the skill file**

Append the run phase to the same skill file:
- Parse arguments: no args = run all, flow name = run specific flow
- Validate manifest on load (check for unresolved placeholders, schema errors)
- Fail fast on missing prerequisites
- Execute each flow: run steps, evaluate assertions, collect results
- Output: markdown table with flow/surface/steps/result/notes
- Summary line: X flows · Y/Z steps passed · N failures

- [ ] **Step 4: Run tests**

Run: `bash tests/test-config.sh`
Expected: test-builder command and skill detected

- [ ] **Step 5: Commit**

```bash
git add skills/test-builder/test-builder.md commands/test-builder.md
git commit -m "feat: add /xgh:test-builder skill for test suite generation"
```

---

### Task 5: Add tests for the new skills

**Files:**
- Modify: `tests/test-config.sh` (add checks for new skills/commands)
- Create: `tests/skill-triggering/prompts/config.txt`
- Create: `tests/skill-triggering/prompts/config-2.txt`
- Create: `tests/skill-triggering/prompts/config-3.txt`
- Create: `tests/skill-triggering/prompts/architecture.txt`
- Create: `tests/skill-triggering/prompts/architecture-2.txt`
- Create: `tests/skill-triggering/prompts/architecture-3.txt`
- Create: `tests/skill-triggering/prompts/test-builder.txt`
- Create: `tests/skill-triggering/prompts/test-builder-2.txt`
- Create: `tests/skill-triggering/prompts/test-builder-3.txt`

- [ ] **Step 1: Read existing test-config.sh to understand patterns**

Read `tests/test-config.sh` to see how it checks for skills and commands.

- [ ] **Step 2: Add structural checks for new skills/commands**

Add checks to `tests/test-config.sh` for:
- `skills/config/config.md` exists
- `commands/config.md` exists
- `skills/architecture/architecture.md` exists
- `commands/architecture.md` exists
- `skills/test-builder/test-builder.md` exists
- `commands/test-builder.md` exists

- [ ] **Step 3: Create skill-triggering prompts**

Create natural-language prompts that should trigger each skill:

config prompts:
- `config.txt`: "show me the current xgh config"
- `config-2.txt`: "add a new project to xgh tracking"
- `config-3.txt`: "set the stack for this project to typescript"

architecture prompts:
- `architecture.txt`: "analyze the architecture of this codebase"
- `architecture-2.txt`: "run a full architectural analysis"
- `architecture-3.txt`: "what are the module boundaries in this project"

test-builder prompts:
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

---

### Task 6: Update config/project.yaml and AGENTS.md references

**Files:**
- Modify: `config/project.yaml` (add new skills to registry)
- Run: `bash scripts/gen-agents-md.sh` (regenerate AGENTS.md if applicable)

- [ ] **Step 1: Read config/project.yaml**

Read `config/project.yaml` to understand the skill registry format.

- [ ] **Step 2: Add new skills to project config**

Add `config`, `architecture`, and `test-builder` to the skills list in `config/project.yaml`.

- [ ] **Step 3: Regenerate AGENTS.md if the script handles skills**

Run: `bash scripts/gen-agents-md.sh` (if it exists and is relevant)

- [ ] **Step 4: Run full test suite**

Run: `bash tests/test-config.sh`
Expected: PASS

- [ ] **Step 5: Final commit**

```bash
git add config/project.yaml AGENTS.md
git commit -m "chore: register pipeline skills in project config"
```
