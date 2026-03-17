# Claude-Internal Scheduler & Background Skill Execution

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan.

**Goal:** Replace OS-level cron/launchd with Claude's built-in CronCreate for session-scoped scheduling, and give each xgh skill the ability to run as a background Agent with per-skill execution mode preferences.

**Architecture:** Session-start hook auto-creates CronCreate jobs for retrieve/analyze. A new `/xgh-schedule` command is the interactive control panel. Headless skills always dispatch as background Agents. Interactive skills check `~/.xgh/prefs.json` on invocation and prompt the user once to capture mode + autonomy preferences.

**Tech Stack:** Bash (hook, prefs helpers), Markdown (skill instructions), JSON (`~/.xgh/prefs.json`), Claude Code CronCreate/CronDelete/CronList tools, Agent tool.

---

## 1. Session-scoped Scheduler

### 1.1 Auto-start via session-start hook

`plugin/hooks/session-start.sh` already supports `XGH_BRIEFING=1` to auto-trigger the briefing skill. Add parallel support for `XGH_SCHEDULER` (default: `1`):

- If `XGH_SCHEDULER=1`, inject a `scheduler_trigger` key into the JSON payload output by the hook.
- The session-start hook instructions (`plugin/skills/init/init.md` or the hook's own inline prompt) detect `scheduler_trigger` and call CronCreate twice:
  - retrieve: `*/5 * * * *`, prompt `/xgh-retrieve`, recurring: true
  - analyze: `*/30 * * * *`, prompt `/xgh-analyze`, recurring: true
- Both jobs are stored with a known label prefix (`xgh:retrieve`, `xgh:analyze`) so `/xgh-schedule` can identify them via CronList.
- Set `XGH_SCHEDULER=0` in the environment to disable for a session.

### 1.2 `/xgh-schedule` — interactive control panel

**New files:**
- `plugin/commands/schedule.md` — slash command definition
- `plugin/skills/schedule/schedule.md` — skill implementation

**Behaviour:**

| Invocation | Action |
|---|---|
| `/xgh-schedule` (no args) | List all active xgh cron jobs via CronList, show next fire time and last result |
| `/xgh-schedule pause retrieve` | CronDelete the retrieve job |
| `/xgh-schedule pause analyze` | CronDelete the analyze job |
| `/xgh-schedule resume retrieve` | Re-create retrieve cron (`*/5 * * * *`) |
| `/xgh-schedule resume analyze` | Re-create analyze cron (`*/30 * * * *`) |
| `/xgh-schedule run retrieve` | Fire `/xgh-retrieve` immediately (one-off, not via cron) |
| `/xgh-schedule run analyze` | Fire `/xgh-analyze` immediately |
| `/xgh-schedule off` | CronDelete all xgh cron jobs for this session |

The skill is interactive (foreground), short, and always runs in the main session — it's the management interface, not a task itself.

### 1.3 Remove OS-level scheduler

- Delete `scripts/ingest-schedule.sh`.
- Delete `scripts/schedulers/` directory (launchd plist templates).
- Remove the `ingest-schedule` component from `techpack.yaml`.
- Remove the scheduler install block from `install.sh` (the section that copies plist templates and calls `ingest-schedule.sh install`).
- Update `install.sh` output text: replace "Models run automatically as a daemon (launchd/systemd)" with a note about session-scoped scheduling.
- Update `plugin/commands/retrieve.md` and `plugin/commands/analyze.md`: replace "Invoked automatically by the scheduler (launchd/cron)" with "Invoked automatically each session via CronCreate".

---

## 2. Background Agent Execution

### 2.1 Headless skills — always background

Skills: `xgh:retrieve`, `xgh:analyze`, `xgh:briefing`, `xgh:brief`

These never interact with the user. Their skill `.md` files are updated to dispatch via the `Agent` tool and return only a summary:

```
## Execution

Dispatch this skill as a background Agent:
- subagent_type: general-purpose
- run_in_background: true
- prompt: [full self-contained task description with all needed context]

Wait for the agent result, then return a one-paragraph summary to the main session.
Do NOT stream raw tool output into the main session context.
```

No preference check, no prompt — always background.

### 2.2 Interactive skills — preference-gated

Skills: `xgh:investigate`, `xgh:implement`, `xgh:index`, `xgh:track`, `xgh:collab`

Each skill's `.md` file gains a **Preamble** section (before any existing content) that runs the preference check:

```markdown
## Preamble — Execution mode

1. Read `~/.xgh/prefs.json`. Check `skill_mode.<this_skill_name>`.
2. If entry exists: proceed to "Dispatch" below using stored values.
3. If not set:
   a. Ask: "Run **investigate** in background or interactive? [b/i, default: i]"
   b. If "b": ask "Check in with one question before starting, or fire-and-forget? [c/f, default: c]"
   c. Write result to `~/.xgh/prefs.json` under `skill_mode.<this_skill_name>`.
4. Flag overrides: `--bg` forces background, `--interactive`/`--fg` forces foreground,
   `--checkin` forces check-in autonomy, `--auto` forces fire-and-forget.

## Dispatch

**Interactive mode:** proceed with normal skill flow (existing instructions below).

**Background / check-in mode:**
  - Ask any essential clarifying questions in the main session first (max 2).
  - Collect full context: task description, relevant files, current branch, recent git log.
  - Dispatch via Agent tool (run_in_background: true) with a self-contained prompt.
  - Wait for result, post summary to main session.

**Background / fire-and-forget mode:**
  - Collect context automatically (no questions).
  - Dispatch via Agent tool (run_in_background: true).
  - Wait for result, post summary to main session.
```

### 2.3 `~/.xgh/prefs.json` schema

```json
{
  "skill_mode": {
    "investigate": { "mode": "background", "autonomy": "check-in" },
    "implement":   { "mode": "interactive" },
    "index":       { "mode": "background", "autonomy": "fire-and-forget" },
    "track":       { "mode": "interactive" },
    "collab":      { "mode": "interactive" }
  }
}
```

- `mode`: `"background"` | `"interactive"`
- `autonomy` (only meaningful when `mode = "background"`): `"check-in"` | `"fire-and-forget"`

---

## 3. Files Changed

| File | Change |
|---|---|
| `plugin/hooks/session-start.sh` | Add `XGH_SCHEDULER` env var support, inject `scheduler_trigger` |
| `plugin/hooks/session-start.sh` (inline prompt) | On `scheduler_trigger`, call CronCreate for retrieve + analyze |
| `plugin/commands/schedule.md` | New — `/xgh-schedule` command |
| `plugin/skills/schedule/schedule.md` | New — schedule control panel skill |
| `plugin/skills/retrieve/retrieve.md` | Add background Agent dispatch pattern |
| `plugin/skills/analyze/analyze.md` | Add background Agent dispatch pattern |
| `plugin/skills/briefing/briefing.md` | Add background Agent dispatch pattern |
| `plugin/skills/brief/brief.md` (if exists) | Add background Agent dispatch pattern |
| `plugin/skills/investigate/investigate.md` | Add preamble preference check |
| `plugin/skills/implement/implement.md` | Add preamble preference check |
| `plugin/skills/index/index.md` | Add preamble preference check |
| `plugin/skills/track/track.md` | Add preamble preference check |
| `plugin/skills/collab/collab.md` | Add preamble preference check |
| `plugin/commands/retrieve.md` | Update scheduler reference text |
| `plugin/commands/analyze.md` | Update scheduler reference text |
| `install.sh` | Remove scheduler install block, update output text |
| `scripts/ingest-schedule.sh` | Delete |
| `scripts/schedulers/` | Delete directory |
| `techpack.yaml` | Remove `ingest-schedule` component |

---

## 4. Out of Scope

- `doctor`, `status`, `ask`, `curate`, `profile`, `calibrate`, `help`, `init`, `design` — these are short, synchronous, or UI-facing. No mode preference needed.
- Persisting cron job IDs across sessions — CronCreate is session-scoped by design; jobs are always re-created at session start.
- Cross-machine preference sync — `~/.xgh/prefs.json` is local only.
