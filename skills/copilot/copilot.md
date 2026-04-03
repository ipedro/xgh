---
name: xgh:copilot
description: "This skill should be used when the user asks to \"dispatch to copilot\", \"run copilot\", \"use copilot for\", \"send to copilot\", \"copilot review\", \"copilot-consult\", or wants to delegate implementation or code review tasks to GitHub's Copilot CLI agent. Supports worktree-isolated parallel dispatch and same-directory sequential dispatch."
---

> **Context-mode:** This skill primarily runs Bash commands. Use Bash directly for git
> and copilot commands (short output). Use `Read` to review copilot output files.

## Preamble — Execution mode

Follow the shared execution mode protocol in `skills/_shared/references/execution-mode-preamble.md`. Apply it to this skill's command name.

- `<SKILL_NAME>` = `copilot`
- `<SKILL_LABEL>` = `Copilot dispatch`

---

# xgh:copilot -- GitHub Copilot CLI Dispatch

Dispatch implementation tasks or code reviews to GitHub's Copilot CLI as a parallel or sequential agent. Copilot runs non-interactively via `-p` (prompt mode), optionally in an isolated git worktree for safe parallel work alongside Claude Code.

> **Shared workflow:** Steps 1, 3, 4, and 5 follow `skills/_shared/references/dispatch-template.md`.
> Use `<CLI>` = `copilot`, `<CLI_LABEL>` = `Copilot`, `<cli>` = `copilot`, `<tag>` = `copilot`.

## Prerequisites

Check Copilot CLI availability:

```bash
command -v copilot >/dev/null 2>&1 && copilot --version || echo "NOT_INSTALLED"
```

If `NOT_INSTALLED`, print: "Copilot CLI not found. Install from: https://docs.github.com/copilot/how-tos/copilot-cli" and stop.

## Input Parsing

Parse the user's request to determine dispatch parameters. Only extract what the user explicitly provides -- all other flags stay at Copilot CLI defaults.

**Spawning management flags** (always injected by the skill):

| Flag | Purpose |
|------|---------|
| `-p "<prompt>"` | Non-interactive prompt mode (exits after completion) |
| `--allow-all-tools` | Auto-approve all actions (no confirmation prompts) |
| `-s` | Silent output (no stats banner), cleaner for redirection |
| `--no-ask-user` | Autonomous mode (no mid-task questions) |

**Note:** Copilot CLI has no `-C` (working directory) flag. Working directory is set via `cd` before invocation. Output is captured via shell redirection.

**User-controlled parameters** (only injected if the user explicitly provides them):

| Parameter | Default | User flag |
|-----------|---------|-----------|
| `type` | `exec` | first arg: `exec` or `review` |
| `isolation` | `worktree` (exec), `same-dir` (review) | `--worktree`, `--same-dir` |
| `prompt` | -- | remaining text after type |
| `effort` | CLI default | `--effort <level>` (translated to Copilot reasoning effort) |

**Effort level translation** (accepts `--effort` — maps to Copilot's `--effort` flag):

| User says | Copilot flag |
|-----------|-------------|
| `--effort low` | `--effort low` |
| `--effort medium` | `--effort medium` |
| `--effort high` | `--effort high` |
| `--effort xhigh` / `--effort max` | `--effort xhigh` |

**Passthrough flags** (forwarded verbatim to Copilot CLI if the user includes them):

| Flag | What it controls |
|------|-----------------|
| `--model <model>` | Model override (e.g., `gpt-5.2`, `claude-sonnet-4-6`) |
| `--effort <level>` | Reasoning effort level |
| `--add-dir <dir>` | Additional workspace directories |
| `--agent <agent>` | Use a custom agent |
| `--resume[=id]` | Resume a previous session |
| `--autopilot` | Enable autopilot continuation |
| `--max-autopilot-continues <n>` | Limit autopilot iterations |

Any unrecognized flags are forwarded to `copilot` as-is.

---

## Step 1: Setup Workspace

Follow `skills/_shared/references/dispatch-template.md` Step 1. Use `<CLI>` = `copilot`.

Same-dir fallback flag: `--same-dir`.

---

## Step 2: Dispatch

### Exec dispatch

Build the command with only spawning management flags plus any user-specified passthrough flags:

```bash
OUTPUT_FILE="/tmp/copilot-exec-${TIMESTAMP}.md"
CMD=(
    copilot
    -p "<prompt>"
    --allow-all-tools
    -s
    --no-ask-user
    # User passthrough flags appended here (e.g., --model gpt-5.2 --effort high)
)
cd "$WORK_DIR" && "${CMD[@]}" > "$OUTPUT_FILE" 2>&1
```

- **Worktree mode:** Run via Bash with `run_in_background: true`. Claude Code is free to continue other work while Copilot runs.
- **Same-dir mode:** Run synchronously. Claude Code waits for completion.

### Review dispatch

For code review, remove `--allow-all-tools` and add prompt engineering for read-only:

```bash
OUTPUT_FILE="/tmp/copilot-review-${TIMESTAMP}.md"
CMD=(
    copilot
    -p "<review prompt>. Do NOT modify any files — this is a read-only review."
    -s
    --no-ask-user
    # User passthrough flags appended here
)
cd "$WORK_DIR" && "${CMD[@]}" > "$OUTPUT_FILE" 2>&1
```

Review prompt examples:
- "Review all changes on this branch vs main. Focus on correctness and test coverage."
- "Review the uncommitted changes. Check for security issues and error handling."

---

## Step 3: Collect Results

Follow `skills/_shared/references/dispatch-template.md` Step 3. Use `<CLI_LABEL>` = `Copilot`.

---

## Step 4: Integration (worktree mode only)

Follow `skills/_shared/references/dispatch-template.md` Step 4.

---

## Step 5: Curate (if memory backend available — see `_shared/references/memory-backend.md`)

Follow `skills/_shared/references/dispatch-template.md` Step 5. Use `<CLI_LABEL>` = `Copilot`, `<cli>` = `copilot`.

**Write observation to model profiles** (always, regardless of MAGI):

After the dispatch completes, append one observation to `.xgh/model-profiles.yaml`. Create the file if it doesn't exist.

```yaml
# Append to .xgh/model-profiles.yaml
- agent: copilot
  model: <the --model flag value, or "default" if none was passed>
  effort: <the --effort value, or "default" if none was passed>
  archetype: <set by router if dispatched via /xgh-dispatch, otherwise "unknown">
  accepted: <true if worktree merged or user continued; false if re-dispatched or discarded>
  ts: <ISO 8601 timestamp>
```

Write using the same python one-liner pattern (stdlib only), with `'agent': 'copilot'`:

```bash
python3 -c "
import json, os, datetime
path = '.xgh/model-profiles.yaml'
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    data = {'observations': []}
data.setdefault('observations', [])
data['observations'].append({
    'agent': 'copilot',
    'model': '<MODEL>',
    'effort': '<EFFORT>',
    'archetype': '<ARCHETYPE>',
    'accepted': True,  # or False based on outcome
    'ts': datetime.datetime.now(datetime.timezone.utc).isoformat()
})
json.dump(data, open(path, 'w'), indent=2)
"
```

Replace `<MODEL>`, `<EFFORT>`, `<ARCHETYPE>` with the actual values from the dispatch. Determine `accepted` from:
- Worktree merged -> `true`
- User continued to next task -> `true`
- User re-dispatched same task -> `false`
- User discarded worktree -> `false`

---

## Approval Modes

Copilot CLI manages permissions via allow/deny tool flags. The skill selects automatically based on dispatch type:

| Dispatch type | Flags | Behavior |
|--------------|-------|----------|
| exec | `--allow-all-tools --no-ask-user` | Auto-approve all actions (full write access) |
| review | `--no-ask-user` (no `--allow-all-tools`) | Prompt-engineered read-only (no file modifications) |

The user can override with `--yolo` (alias for `--allow-all-tools --allow-all-paths --allow-all-urls`).

## Model Selection

Copilot CLI supports multiple models via `--model`:

| Model | Best for |
|-------|----------|
| `gpt-5.2` | Default, general purpose |
| `claude-sonnet-4-6` | Fast coding tasks |
| `claude-opus-4-6` | Complex reasoning |
| `o3` | Deep analysis |
| `o4-mini` | Quick tasks, low cost |

If user doesn't specify, Copilot uses its default model.

## Anti-Patterns

See shared anti-patterns in `skills/_shared/references/dispatch-template.md`.

Copilot-specific additions:
- **Missing `--no-ask-user`.** Without this flag, Copilot may pause mid-task to ask questions, blocking the non-interactive dispatch indefinitely.
- **Using `--yolo` for reviews.** This gives write access. Reviews should omit `--allow-all-tools` and rely on prompt engineering for read-only behavior.
