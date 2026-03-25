---
hook: SessionStart
analyzed_by: sonnet
date: 2026-03-25
context: xgh project.yaml config system design
---

# SessionStart Hook Analysis

## 1. Hook Spec

**When it fires:** Once per Claude Code session, before the first user turn. The model has not yet seen the user prompt; this is the earliest interception point available in the hook lifecycle.

**Input received:** Minimal. The hook receives a JSON payload with `session_id` and the current working directory. No conversation history, no user message, no tool results. The model context is empty at this point.

**Output it can return:** A JSON object with two meaningful fields:

- `additionalContext` — a string injected into the model's system context before the first turn. This is the primary power of the hook: content placed here is treated as if it were part of the system prompt for the entire session.
- `systemMessage` — an alternative or supplementary system-level message.

The hook runs as a subprocess. Whatever the hook prints to stdout (valid JSON) becomes the payload returned to Claude Code. The current `session-start.sh` exploits this by printing a structured JSON object with `contextFiles`, `briefingTrigger`, `schedulerInstructions`, and related fields.

---

## 2. Capabilities

**One-time setup:** The hook is the right place for work that should happen exactly once per session — not per skill invocation, not per tool call. Retention cleanup (`find ~/.xgh/inbox/processed -mtime +7 -delete`) and directory scaffolding (`mkdir -p ~/.xgh/triggers`) belong here precisely because they are session-level concerns, not per-command concerns.

**Context injection:** The most valuable capability. Anything injected via `additionalContext` is available to every skill and agent in the session without each skill needing to re-read the same files. The current hook injects context tree excerpts sorted by maturity × importance score.

**Environment validation:** The hook can detect whether required tools (`yq`, `python3`, `gh`) are present and inject a warning if they are not. A degraded-environment warning in the session context means the model will surface it to the user on the first relevant action rather than failing silently mid-skill.

**Warm caches:** The hook can pre-fetch slow data (remote repo metadata, latest release tag, provider cursor state) and write it to `~/.xgh/` files. Subsequent skills can read those files instead of making network calls, reducing per-skill latency.

---

## 3. Opportunities for xgh

### 3a. Inject project.yaml preferences as session context

Currently `lib/config-reader.sh` re-parses `config/project.yaml` on every `load_pr_pref` call. The SessionStart hook fires once; it could read the entire `preferences:` block, format it as a brief summary, and inject it via `additionalContext`. Every skill in the session would then already "know" the project's merge method, reviewer, default agent, and model preferences without making a single disk read.

Example output fragment to inject:

```
Project preferences (from config/project.yaml):
  pr.merge_method: squash  (main: merge)
  pr.reviewer: copilot-pull-request-reviewer[bot]
  pr.auto_merge: true
  dispatch.default_agent: xgh:dispatch
  pair_programming.enabled: true
```

This is the declarative-AI-ops pitch made concrete: the config file declared once, resolved once, available everywhere.

### 3b. Staleness check against git remote

The hook already detects the project root. A one-time `git fetch --dry-run` (or `git ls-remote origin HEAD`) at session start can compare the remote HEAD SHA with the local HEAD SHA. If the local branch is behind `develop` or `main` by more than N commits, inject a staleness warning into context:

```
Warning: local branch is 8 commits behind origin/develop. Consider running git pull before making changes.
```

This maps to xgh's "converge to desired state" philosophy: the model is informed of drift before it starts making changes that will conflict.

### 3c. Config validation and preference completeness check

The hook can validate `config/project.yaml` against a known schema at session start. Missing or malformed keys (e.g., `pr.reviewer` set to a plain string without `[bot]` suffix for Copilot, or `preferences.pr.branches.main.merge_method` absent) can be flagged once rather than discovered mid-skill. Because the hook can return a warning in `additionalContext`, the model will surface the issue on the first PR-related action without the user needing to debug a failed skill.

---

## 4. Pitfalls

**Runs once, must be reliable:** There is no retry. If `session-start.sh` throws an uncaught error, the session starts in a degraded state with no injected context. The current hook uses `set -euo pipefail` and Python with `try/except` on every file read — both are correct. The risk is the Python subprocess: if `python3` is absent or PyYAML is missing and the hook does not handle it, it exits non-zero and Claude Code may surface the raw error.

**Timeout limits:** Claude Code enforces a timeout on hook execution. The current hook does `find` + `glob` + file reads across the context tree. On a large context tree or slow filesystem (network mount, Docker volume), this can breach the timeout. The hook mitigates this with `max_files = 5`, but deeper scans (e.g., adding a `git ls-remote` call) must be done with a local timeout guard (`timeout 3 git ls-remote ...`).

**Degraded session is invisible:** When the hook fails, the model proceeds without any injected context. The user sees no explicit error message — they simply don't get the benefits (briefing trigger, scheduler setup, context files). This was observed during the version mismatch bug: the hook ran but produced stale or wrong output, and the session appeared normal while operating on incorrect assumptions. Defensive output — always printing a valid JSON object even on partial failure — is essential.

**No user interaction:** The hook cannot ask the user a question or wait for input. Anything that requires clarification (e.g., "which project are you working on?") must either be resolved via heuristics (`detect-project.sh`) or deferred to a skill that runs interactively. The hook is strictly fire-and-inject.

**Order sensitivity with other hooks:** If another hook (e.g., a prompt-submit hook) also reads `config/project.yaml`, there is no guarantee that the session-start injection has been consumed by the model before the prompt-submit hook fires on the first message. Skills should not depend on session-start context being present and should fall back to `load_pr_pref` if needed.

---

## 5. Concrete Implementations

### Implementation A: Preferences Injection Block

Extend the Python block in `session-start.sh` to read `config/project.yaml` and build a `preferencesContext` string. Add it to the JSON output, and have the hook consumer include it in `additionalContext`. This replaces repeated `load_pr_pref` disk reads for the entire session.

Key addition to the Python block:

```python
# Load project preferences once
proj_yaml = Path(os.getcwd()) / "config" / "project.yaml"
preferences_summary = ""
if proj_yaml.exists():
    try:
        import subprocess as _sp
        _r = _sp.run(["python3", "-c",
            "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])) or {}; "
            "import json; print(json.dumps(d.get('preferences', {})))",
            str(proj_yaml)], capture_output=True, text=True)
        if _r.returncode == 0:
            prefs = json.loads(_r.stdout)
            pr = prefs.get("pr", {})
            preferences_summary = (
                f"Project preferences (config/project.yaml): "
                f"pr.merge_method={pr.get('merge_method','?')} "
                f"pr.reviewer={pr.get('reviewer','?')} "
                f"pr.auto_merge={pr.get('auto_merge','?')}"
            )
    except Exception:
        pass
```

### Implementation B: Remote Staleness Guard

Add a guarded `git ls-remote` call that completes within 2 seconds or skips silently:

```python
import subprocess, shlex
staleness_warning = ""
try:
    local = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, timeout=2
    )
    remote = subprocess.run(
        ["git", "ls-remote", "origin", "HEAD"], capture_output=True, text=True, timeout=2
    )
    if local.returncode == 0 and remote.returncode == 0:
        local_sha = local.stdout.strip()
        remote_sha = remote.stdout.split()[0] if remote.stdout.strip() else ""
        if remote_sha and local_sha != remote_sha:
            staleness_warning = (
                "Note: local HEAD differs from origin/HEAD. "
                "Consider pulling before making changes."
            )
except Exception:
    pass  # network unavailable or not a git repo — skip silently
```

### Implementation C: Config Validation Warning

A lightweight schema check that runs in the Python block and appends warnings to `additionalContext` if required keys are absent or malformed:

```python
config_warnings = []
if proj_yaml.exists():
    try:
        with open(proj_yaml) as f:
            d = yaml.safe_load(f) or {}
        pr = d.get("preferences", {}).get("pr", {})
        if not pr.get("reviewer"):
            config_warnings.append("config/project.yaml: preferences.pr.reviewer is unset")
        reviewer = pr.get("reviewer", "")
        if "copilot" in reviewer.lower() and "[bot]" not in reviewer:
            config_warnings.append(
                f"config/project.yaml: reviewer '{reviewer}' looks like Copilot "
                "but is missing the [bot] suffix — re-review trigger may not fire"
            )
        if not pr.get("repo"):
            config_warnings.append("config/project.yaml: preferences.pr.repo is unset — skills will fall back to probe")
    except Exception as e:
        config_warnings.append(f"config/project.yaml: parse error — {e}")
```

This turns silent misconfiguration into a visible model warning before the first PR skill runs, fulfilling the "declare once, converge always" contract at session startup.

---

## Summary

The SessionStart hook is xgh's highest-leverage injection point: it fires once, costs nothing per skill, and has direct write access to the model's context for the entire session. The current implementation correctly uses it for context tree loading and scheduler setup. The natural extension is to make it the canonical loader for `config/project.yaml` preferences — consistent with xgh's declarative-AI-ops mission and eliminating the per-call overhead that `load_pr_pref` currently pays on every skill invocation.
