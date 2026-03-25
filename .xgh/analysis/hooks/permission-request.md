---
hook: PermissionRequest
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# PermissionRequest Hook — Analysis for xgh

## 1. Hook Spec

**When it fires:** Before Claude Code shows a permission prompt to the user. It intercepts the moment Claude is about to ask "May I run this command / write this file / call this tool?" — giving the hook a chance to answer on the user's behalf.

**Input received:**

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git push --force origin main"
  }
}
```

`tool_name` is one of the Claude Code tool identifiers (`Bash`, `Edit`, `Write`, `Read`, `Glob`, `Grep`, etc.). `tool_input` is the exact payload that would be passed to the tool — for `Bash` this is the shell command string; for `Edit` it includes `file_path`, `old_string`, `new_string`.

**Output it can return:**

```json
{ "decision": "allow" }   // grant silently — no prompt shown
{ "decision": "deny",  "message": "Force-push to main is blocked by project policy." }
{ "decision": "ask"   }   // fall through to normal user prompt (default if hook exits 0 with no output)
```

A non-zero exit code or malformed output falls back to `ask`, preserving the default behavior. The `message` field on a deny is shown to Claude as the reason, which it can surface in its reply.

---

## 2. Capabilities

**Auto-approve** skips the prompt entirely. The user never sees it. This is appropriate when the operation is provably safe by policy — reading source files, running the test suite, querying git log.

**Auto-deny** blocks the operation before it reaches Claude's tool executor. Unlike a post-tool hook that can only observe, a PermissionRequest deny is a true veto. Claude receives the denial message and must adapt its plan.

**Conditional routing** is possible: the hook can approve for local dev environments and escalate to `ask` in CI, or approve on feature branches but deny on `main`/`develop`.

The hook runs as a subprocess. It can read files, call APIs, or consult a local database — as long as it exits quickly. Slow hooks degrade the interactive experience.

---

## 3. Opportunities for xgh

### 3.1 Config-driven permission policies via project.yaml

xgh already centralizes preferences in `config/project.yaml` with `lib/config-reader.sh` as the reader. The same cascade that drives `MERGE_METHOD` and `REVIEWER` can drive permissions:

```yaml
# config/project.yaml
permissions:
  auto_approve:
    - tool: Bash
      pattern: "^git (log|status|diff|show)"
    - tool: Bash
      pattern: "^npm test"
    - tool: Read
      pattern: ".*"          # reading is always safe
  auto_deny:
    - tool: Bash
      pattern: "--force"
      message: "Force operations blocked — see permissions.auto_deny in project.yaml"
    - tool: Bash
      pattern: "^rm -rf"
      message: "Recursive deletes require manual confirmation."
```

The hook sources `lib/config-reader.sh`, calls `xgh_config_get "permissions.auto_approve"`, matches the incoming `tool_input` against the patterns, and emits `allow`/`deny`/`ask`. This is pure declarative ops — the same YAML-converge-everything philosophy that defines xgh's mission.

### 3.2 Environment-aware permissions (CI vs local)

CI pipelines running Claude Code agents (e.g. via the `--headless` flag) should be more restrictive than local interactive sessions. The hook can detect context:

```bash
if [[ -n "$CI" || -n "$GITHUB_ACTIONS" ]]; then
  # Tighten: deny any Bash command not in an explicit allowlist
  ...
else
  # Local: use project.yaml policy as-is
  ...
fi
```

xgh's `providers/github/` already understands the GitHub Actions environment. The hook becomes the enforcement layer for whatever the provider knows about the runtime context.

### 3.3 Branch-aware guardrails tied to pr.branches config

`config/project.yaml` already has per-branch merge preferences (`pr.branches.main.merge_method: squash`). The same branch stanza can carry protection rules:

```yaml
pr:
  branches:
    main:
      merge_method: squash
      protected: true          # new field
    develop:
      merge_method: squash
      protected: true
```

The hook reads the current branch (`git branch --show-current`), checks `pr.branches.<branch>.protected`, and if `true`, auto-denies any `git push --force`, `git reset --hard`, or `git rebase` command targeting that branch. This mirrors GitHub branch protection rules but enforces them client-side, before Claude even attempts the operation.

---

## 4. Pitfalls

**Silent over-approval is the biggest risk.** When `allow` is returned, the user never sees a prompt. A regex that is too broad — `pattern: "^git"` — approves `git push --force --delete` alongside `git log`. Every auto-approve pattern must be as specific as possible and reviewed like a firewall rule.

**Pattern matching on shell commands is brittle.** Claude may invoke `bash -c "git push --force"` or pipe commands. A simple prefix match on `tool_input.command` can be evaded. The hook should match substrings, not just prefixes, and consider rejecting any command that contains high-risk tokens (`--force`, `--delete`, `DROP TABLE`) regardless of what precedes them.

**Deny messages reach Claude, not the user.** If the message is unclear, Claude will waste tokens trying to work around a block it doesn't understand. Deny messages should be prescriptive: "Use `git push` without `--force`. Force-push is blocked by project policy in `config/project.yaml > permissions.auto_deny`."

**Hard to debug when permissions are silently granted.** If a destructive operation succeeds and no one knows the hook approved it, the audit trail is gone. The hook should append every `allow` decision to a log file (e.g. `.xgh/logs/permission-grants.log`) with timestamp, tool, and matched pattern.

**Hook failures default to ask, not deny.** If the hook crashes (missing dependency, malformed YAML), Claude Code falls back to showing the prompt. This is safe but means policy is silently unenforced. The hook should validate its own config at startup and emit a warning if `project.yaml` is missing or unparseable.

---

## 5. Concrete Implementations

### Implementation A — `hooks/permission-request.sh` (config-driven allow/deny)

A single hook script that:
1. Sources `lib/config-reader.sh`
2. Reads `permissions.auto_approve` and `permissions.auto_deny` arrays from `project.yaml` using `xgh_config_get`
3. Matches `tool_name` and `tool_input` against each pattern
4. Emits `{"decision":"allow"}` or `{"decision":"deny","message":"..."}` to stdout
5. Appends every non-ask decision to `.xgh/logs/permission-grants.log`

This is the minimal viable implementation — pure config convergence, no hard-coded rules.

### Implementation B — `hooks/permission-request-branch-guard.sh` (branch protection)

Reads the current git branch, checks `pr.branches.<branch>.protected` in `project.yaml`. If protected and the command matches any of `--force`, `--delete`, `reset --hard`, emits a deny with a message pointing to the relevant YAML key. Chains into Implementation A so the two policies compose rather than conflict.

### Implementation C — CI tightening via `$GITHUB_ACTIONS` detection

Wraps Implementation A: when `$GITHUB_ACTIONS=true`, replaces the allow-list with a strict allowlist (only `Read`, `Glob`, `Grep`, and pre-approved `Bash` patterns like `npm test` and `gh pr`). Anything else returns `ask` — which in headless mode causes Claude to abort and log a policy violation rather than block the pipeline. This gives CI operators a clear signal when an agent tries to do something outside its intended scope.

---

## Summary

The PermissionRequest hook is the right place for xgh's declarative policy engine. It sits at the only point where a decision can be made *before* an operation happens. By routing policy through `config/project.yaml` — the same file that already owns merge methods, reviewers, and branch preferences — xgh can offer a single YAML source that governs not just how PRs are merged, but what Claude is allowed to do in the first place. That is the Terraform analogy made concrete: declare the desired permission state, converge every agent session to match.
