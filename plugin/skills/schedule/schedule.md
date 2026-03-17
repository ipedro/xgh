---
name: xgh:schedule
description: Interactive scheduler control panel. Lists, pauses, resumes, and fires xgh CronCreate jobs. Also manages ~/.xgh/prefs.json skill execution mode preferences.
type: flexible
triggers:
  - /xgh-schedule command
  - when user asks to check, pause, resume, or manage the scheduler
  - when user asks about skill mode preferences
---

> **Output format:** Start with `## 🐴🤖 xgh schedule`. Use ✅ ⚠️ ❌ for status. Keep output concise.

# xgh:schedule — Scheduler Control Panel

## Routing

Parse the invocation text to determine the subcommand:

| Invocation pattern | Action |
|---|---|
| no args or `status` | → **Status** |
| `pause retrieve` | → **Pause** retrieve |
| `pause analyze` | → **Pause** analyze |
| `resume retrieve` | → **Resume** retrieve |
| `resume analyze` | → **Resume** analyze |
| `run retrieve` | → **Run** retrieve now |
| `run analyze` | → **Run** analyze now |
| `off` | → **Off** (cancel all) |
| `prefs reset <skill>` | → **Reset pref** for skill |
| `prefs` | → **Show prefs** |

---

## Status

Call CronList. Find jobs where prompt is exactly `/xgh-retrieve` or `/xgh-analyze`.

If 0 matching jobs found:
> ⚠️ No active xgh scheduler jobs. Enable with `XGH_SCHEDULER=on` or run `/xgh-schedule resume retrieve` and `/xgh-schedule resume analyze`.

If jobs found, display:

```
## 🐴🤖 xgh schedule

| Job | Cron | Status | Note |
|-----|------|--------|------|
| retrieve | */5 * * * * | ✅ active | auto-expires in 3 days |
| analyze | */30 * * * * | ✅ active | auto-expires in 3 days |
```

Note: CronCreate jobs auto-expire after 3 days. They are re-created automatically on the next session start if `XGH_SCHEDULER=on`.

---

## Pause

Call CronDelete for the job whose prompt matches the target (`/xgh-retrieve` or `/xgh-analyze`).

To find the job ID: scan CronList output for the matching prompt, extract the job ID.

Report: `⏸ retrieve paused. Resume with /xgh-schedule resume retrieve.`

---

## Resume

Call CronCreate:
- retrieve: `cron: "*/5 * * * *"`, `prompt: "/xgh-retrieve"`, `recurring: true`
- analyze: `cron: "*/30 * * * *"`, `prompt: "/xgh-analyze"`, `recurring: true`

Report: `✅ retrieve resumed (*/5 * * * *).`

---

## Run

Invoke the target skill directly in this session (not via cron):
- `run retrieve` → invoke `/xgh-retrieve`
- `run analyze` → invoke `/xgh-analyze`

---

## Off

Call CronDelete for both jobs. Report count of jobs cancelled.

---

## Show prefs

Read `~/.xgh/prefs.json` using Bash:
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    sm = p.get('skill_mode', {})
    if not sm:
        print('(no preferences saved yet)')
    else:
        for k, v in sm.items():
            mode = v.get('mode', '?')
            auto = v.get('autonomy', '')
            print(f'  {k}: {mode}' + (f' / {auto}' if auto else ''))
except FileNotFoundError:
    print('(no preferences saved yet)')
"
```

Display the output in a table.

---

## Reset pref

Delete the preference entry for the named skill:

```bash
python3 -c "
import json, os, sys
skill = sys.argv[1]
path = os.path.expanduser('~/.xgh/prefs.json')
try:
    p = json.load(open(path))
    p.get('skill_mode', {}).pop(skill, None)
    json.dump(p, open(path, 'w'), indent=2)
    print(f'Reset: {skill} will prompt on next invocation.')
except FileNotFoundError:
    print('Nothing to reset.')
" "<skill_name>"
```
