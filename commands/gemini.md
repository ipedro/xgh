---
name: gemini
description: "Dispatch tasks to Gemini CLI for parallel implementation or code review"
usage: "/xgh-gemini [exec|review] <prompt>"
aliases: ["gem"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh gemini`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh gemini

Dispatch implementation tasks or code reviews to Google's Gemini CLI. Supports worktree-isolated parallel dispatch (Gemini works in a branch while Claude Code continues) and same-directory sequential dispatch.

## Usage

```
/xgh-gemini exec "Add unit tests for the auth module"
/xgh-gemini review "Check for security issues in the latest changes"
/xgh-gemini exec --model gemini-2.5-flash "Fix lint warnings in src/utils/"
/xgh-gemini exec --same-dir "Add missing docstrings"
/xgh-gemini review --worktree "Full architecture review of src/middleware/"
```

## Behavior

1. Load the `xgh:gemini` skill from `skills/gemini/gemini.md`
2. Check prerequisites: verify Gemini CLI is installed
3. Parse dispatch parameters: type (exec/review), isolation mode, prompt
4. Setup workspace:
   - **Worktree mode** (default for exec): create isolated git worktree
   - **Same-dir mode** (default for review): use current directory
5. Dispatch to Gemini CLI:
   - exec: `gemini -p "<prompt>" --yolo` (auto-approve, full write)
   - review: `gemini -p "<prompt>" --approval-mode plan` (read-only)
6. For worktree mode: present integration options (merge, cherry-pick, keep, discard)

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `type` | No | `exec` (default) or `review` |
| `prompt` | Yes | Task description or review instructions |
| `--model`, `-m` | No | Override model (e.g., `gemini-2.5-flash`). Omit to use CLI default. |
| `--effort`, `--thinking` | No | Reasoning effort: `low`, `medium`, `high`, `max`/`xhigh`, `minimal`. Both flags are aliases. |
| `--approval-mode` | No | Override approval mode (`default`, `auto_edit`, `yolo`, `plan`) |
| `-s` | No | Enable sandbox mode |
| `[any gemini flag]` | No | All unrecognized flags are forwarded to Gemini CLI as-is |
| `--worktree` | No | Force worktree isolation (default for exec) |
| `--same-dir` | No | Force same-directory mode (default for review) |

## Examples

```
# Dispatch implementation task (worktree mode)
/xgh-gemini exec "Add unit tests for the auth module"

# Code review (read-only plan mode)
/xgh-gemini review "Review changes on this branch for correctness and security"

# Use a specific model
/xgh-gemini exec --model gemini-2.5-flash "Generate boilerplate for new API endpoint"

# Same-dir mode for a quick fix
/xgh-gemini exec --same-dir "Fix all ESLint warnings in src/utils/"

# Sandboxed execution
/xgh-gemini exec -s "Refactor database connection pooling"
```

## Related Skills

- `xgh:gemini` -- the dispatch workflow skill this command triggers
- `xgh:codex` -- similar dispatch skill for OpenAI's Codex CLI
- `xgh:implement` -- full ticket implementation (can delegate subtasks)
- `xgh:collab` -- multi-agent collaboration
