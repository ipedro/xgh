---
hook: PostToolUse
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# PostToolUse Hook — Analysis for xgh

## 1. Hook Spec

**When it fires:** After Claude Code successfully executes any tool. "Successfully" means the tool itself ran without throwing — it does not mean the command inside returned exit code 0. A Bash tool call that exits 1 still triggers PostToolUse.

**Input (stdin):** JSON object with three top-level keys:

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "git push origin main" },
  "tool_response": { "stdout": "...", "stderr": "...", "exit_code": 0 }
}
```

For non-Bash tools the shape changes: `Edit` carries `file_path`, `old_string`, `new_string`; `Read` carries `file_path`; `Glob` carries `pattern`. The `tool_response` field structure varies by tool — for Bash it has `exit_code`; for Read it has the file content string; for Edit it may be empty on success.

**Output:** The hook can write to stdout:
- A JSON object with `additionalContext` — injected into Claude's next prompt as background context.
- A JSON object with `systemMessage` — shown in the Claude Code UI as a notice.
- Exit non-zero to signal an error, which Claude Code surfaces as a tool-use warning.

Returning nothing (exit 0, empty stdout) is silent and the most common path.

## 2. Capabilities

PostToolUse can do anything a shell script can do after the fact:

- **Inject follow-up context** — return `{"additionalContext": "..."}` to steer the next model turn without user intervention. Useful for reminding Claude of constraints discovered at execution time.
- **Display messages** — return `{"systemMessage": "..."}` to surface audit notes, warnings, or confirmations in the UI.
- **Log actions** — append structured records to a log file, SQLite DB, or the xgh inbox.
- **Mutate files** — write back to `config/project.yaml`, context tree entries, or `.xgh/` state files based on what just executed.
- **Trigger downstream workflows** — write inbox items that the xgh trigger engine picks up (exactly what the existing `hooks/post-tool-use.sh` does for `source: local` triggers).

Notably, it **cannot** undo the tool action. The file was already written, the command already ran.

## 3. Opportunities for xgh

### 3.1 Preference Capture — Learning from Edit Patterns

xgh's declarative model depends on `config/project.yaml` being accurate. When Claude uses Edit to change a skill file or YAML config, PostToolUse can inspect `tool_input.old_string` vs `tool_input.new_string` to detect preference drift — for example, a reviewer login being changed inline rather than through the registry. The hook can then write that change back into `preferences.pr` so the next run reads the updated value.

This closes the gap identified in `load_pr_pref`: the fallback `probe_pr_field → cache_pr_pref` chain already writes discovered values into `project.yaml`, but it only fires for PR-related fields. PostToolUse on Edit could generalize this to all preference namespaces.

### 3.2 Audit Log for Config Changes

`config/project.yaml` is git-committed and human-readable, but there's no timestamped record of *when* a field changed and *which skill* triggered the change. A PostToolUse hook watching Edit calls on `project.yaml` can append to `.xgh/audit/config-changes.jsonl`:

```json
{"ts": "2026-03-25T14:02:00Z", "field": "pr.merge_method", "old": "squash", "new": "merge", "session": "abc123"}
```

This matters because `project.yaml` is the single source of truth for skills like `/release` (which just gained `--squash` support on the current branch `fix/release-squash`). Knowing when and how that field was changed — and from which Claude session — is exactly the kind of traceability Terraform provides for infrastructure state.

### 3.3 Post-Execution Validation — Preventing Drift

After any Bash tool call that runs a git push or `gh pr create`, a PostToolUse hook can verify that the operation used the merge method declared in `project.yaml`. For the current repo, `main` requires `merge_method: merge` and `develop` requires `squash`. If Claude runs `gh pr merge --merge` on a develop PR, PostToolUse can fire a `systemMessage` warning:

> "Merge method used (merge) does not match project.yaml preference for branch develop (squash). Update project.yaml or use --squash."

This is analogous to Terraform plan vs apply drift detection — declaration vs actual state.

## 4. Pitfalls

**Runs on every matching tool call.** If the hook matches Bash broadly, it fires on every single command — including trivial ones like `ls`. The existing xgh implementation correctly fast-exits when no local triggers exist, but any hook that does real work (e.g., YAML parsing) needs to be similarly aggressive about early-exit conditions.

**Cannot undo.** If a destructive Bash command ran (e.g., `git push --force`), PostToolUse can log it and warn, but cannot reverse it. PreToolUse is the right hook for blocking; PostToolUse is for observation and follow-up.

**Performance overhead.** Every hook invocation forks a subprocess. Python3 YAML parsing (as used in `config-reader.sh` and the existing hook) adds ~80–150ms per call. Over a long session with hundreds of tool uses, this compounds. The existing hook's double fast-exit guard (check for triggers dir, then check for `source: local` entries) is the right pattern.

**Parsing tool_response is fragile.** The JSON structure of `tool_response` is not formally documented and differs by tool. The existing hook defensively wraps every `python3 -c` extraction in `|| echo ""` fallbacks. Any new hook code should follow the same pattern and never assume field presence.

**additionalContext token cost.** Every `additionalContext` string returned by a hook is injected into Claude's context window. Returning verbose logs or full file contents here will balloon token usage — counter to xgh's RTK philosophy.

## 5. Concrete Implementation Examples

### Example A — Auto-cache preference writes

Fires on `Edit` tool. If the edited file is `config/project.yaml`, extracts changed key paths and emits a `systemMessage` summarizing what was updated. No `additionalContext` needed — just visibility.

```bash
# In post-tool-use.sh, add after the existing Bash-only check:
if [ "$TOOL_NAME" = "Edit" ]; then
  FILE=$(echo "$HOOK_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))")
  if echo "$FILE" | grep -q "config/project.yaml"; then
    # Emit a systemMessage so the user sees the config was touched
    echo '{"systemMessage": "project.yaml updated — preferences registry modified this turn."}'
  fi
  exit 0
fi
```

### Example B — Trigger inbox item on gh pr merge

Fires on `Bash` tool. If the command matches `gh pr merge`, writes an inbox item with the PR number and method used, for the xgh trigger engine to pick up and post a summary to Slack or Telegram.

The existing trigger YAML pattern in `~/.xgh/triggers/*.yaml` already supports this — the hook's current `CMD_PATTERN` regex matching would match `gh pr merge` with a pattern like `^gh pr merge`.

### Example C — Branch merge-method drift warning

Fires on `Bash` tool when the command contains `gh pr merge` or `git merge`. Reads `config/project.yaml` to get the declared merge method for the current branch. If the command flags don't match, returns a `systemMessage`.

```bash
CURRENT_BRANCH=$(git -C "$(git rev-parse --show-toplevel)" branch --show-current 2>/dev/null || echo "")
DECLARED=$(python3 -c "
import yaml, sys
branch = sys.argv[1]
with open(sys.argv[2]) as f: d = yaml.safe_load(f) or {}
print(d.get('preferences',{}).get('pr',{}).get('branches',{}).get(branch,{}).get('merge_method') or
      d.get('preferences',{}).get('pr',{}).get('merge_method','squash'))
" "$CURRENT_BRANCH" "$(git rev-parse --show-toplevel)/config/project.yaml" 2>/dev/null || echo "squash")

if echo "$COMMAND" | grep -q "gh pr merge" && ! echo "$COMMAND" | grep -q -- "--$DECLARED"; then
  echo "{\"systemMessage\": \"Warning: merge command may not match project.yaml declared method ($DECLARED) for branch $CURRENT_BRANCH.\"}"
fi
```

## Summary

PostToolUse is xgh's observation layer — it cannot enforce (that's PreToolUse), but it can log, warn, cache, and propagate. Its highest-value application in xgh is closing the feedback loop between *what Claude actually did* and *what project.yaml declares* — keeping the declarative config honest, the same way Terraform state keeps infrastructure honest.

The existing `hooks/post-tool-use.sh` uses it correctly as a trigger-bus dispatcher. The next natural extension is config-drift detection on Edit calls to `project.yaml` and merge-method validation on `gh pr merge` commands.
