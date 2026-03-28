---
name: xgh:token-window
description: "Token budget visibility — shows session/weekly/Sonnet window state, adjusts briefing depth based on budget level, and warns when approaching quota limits"
---

> **Output format:** Follow the [xgh output style guide](../../templates/output-style.md). Start with `## 🐴🤖 xgh token-window`. Use markdown tables for structured data. Use 🟢 🟡 🔴 🚨 for budget status.

# xgh:token-window — Token Budget Visibility

Reads `~/.xgh/budget.yaml` for current session/weekly/Sonnet consumption and surfaces budget-aware recommendations.

---

## Routing

Parse the invocation text to determine the subcommand:

| Invocation pattern | Action |
|---|---|
| no args | → **Status** (full table) |
| `--warn` | → **Status** only if budget level is TIGHT, CRITICAL, or DEFICIT |
| `--status` | → **One-line summary** for pasting in command-center header |
| `set <session%> <weekly%> <sonnet%>` | → **Set** update budget.yaml with provided values |
| `reset` | → **Reset** mark budget as unknown |

---

## Budget File Format

`~/.xgh/budget.yaml` structure:

```yaml
session_pct_used: 45      # 0-100, float
weekly_pct_used: 62       # 0-100, float
sonnet_pct_used: 30       # 0-100, float
weekly_deficit: false     # true if borrowing from future window
last_updated: "2026-03-27T14:30:00"  # ISO8601
```

---

## Budget Levels

Determine the **budget level** from the worst of the three windows:

| Level | Condition |
|-------|-----------|
| DEFICIT | `weekly_deficit: true` |
| CRITICAL | Any window > 95% |
| TIGHT | Any window > 80% |
| NORMAL | Any window 40–80% |
| FRESH | All windows < 40% |

---

## Status (no args — full table)

1. Check if `~/.xgh/budget.yaml` exists:
   ```bash
   python3 -c "
   import yaml, os, sys
   path = os.path.expanduser('~/.xgh/budget.yaml')
   if not os.path.exists(path):
       print('UNKNOWN')
       sys.exit(0)
   with open(path) as f:
       d = yaml.safe_load(f) or {}
   print(yaml.dump(d))
   "
   ```

2. If file does not exist or output is `UNKNOWN`:
   ```
   ## 🐴🤖 xgh token-window

   ⚠️ Budget state unknown — update with:
      /xgh-token-window set <session%> <weekly%> <sonnet%>

   Tip: Read your CodexBar screenshot and run the set command to track consumption.
   ```
   Stop here.

3. If file exists, parse fields and display:

   ```
   ## 🐴🤖 xgh token-window

   | Window  | Used% | Left% | Status |
   |---------|-------|-------|--------|
   | Session | 45%   | 55%   | 🟡     |
   | Weekly  | 62%   | 38%   | 🟡     |
   | Sonnet  | 30%   | 70%   | 🟢     |

   Budget level: NORMAL
   Last updated: 2026-03-27 14:30 UTC
   ```

   Status icons:
   - 🟢 < 60% used
   - 🟡 60–80% used
   - 🔴 > 80% used
   - 🚨 DEFICIT (weekly_deficit: true)

4. Append budget-level footer:

   **FRESH / NORMAL:** No action needed.
   ```
   _Budget healthy — proceed with planned work._
   ```

   **TIGHT (>80%):**
   ```
   ⚠️ Budget tight — recommended actions:
   - Pause non-critical analyze cron: /xgh-schedule pause analyze
   - Skip optional briefing sections (Slack, Figma)
   - Prefer --status over full briefings
   - Defer non-blocking implementation to next window
   ```

   **CRITICAL (>95%):**
   ```
   🔴 Budget critical — recommended actions:
   - Pause ALL crons immediately: /xgh-schedule pause
   - Only hotfix-class work proceeds
   - Reserve remaining 5% for emergency patches
   - Alert Pedro if weekly window critical
   ```

   **DEFICIT:**
   ```
   🚨 Budget in deficit — borrowing from future window:
   - Only critical-path work proceeds
   - Stop all non-essential agents
   - Pause ALL crons: /xgh-schedule pause
   - Notify Pedro immediately
   ```

---

## --warn mode

Only emit output if budget level is TIGHT, CRITICAL, or DEFICIT. Otherwise: silent (no output).

Emit the same Status output as above when the threshold is met.

---

## --status mode (one-line summary)

Output a single line for embedding in command-center header:

```
Token: Session 45% 🟡 | Weekly 62% 🟡 | Sonnet 30% 🟢 — NORMAL
```

If budget.yaml is missing:
```
Token: unknown (run /xgh-token-window set)
```

If TIGHT/CRITICAL/DEFICIT, prefix with warning icon:
```
⚠️ Token: Session 83% 🔴 | Weekly 71% 🟡 | Sonnet 45% 🟢 — TIGHT
```

---

## set <session%> <weekly%> <sonnet%>

Write values to `~/.xgh/budget.yaml`:

```bash
python3 -c "
import yaml, os, sys, datetime
s, w, sn = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
path = os.path.expanduser('~/.xgh/budget.yaml')
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {
    'session_pct_used': s,
    'weekly_pct_used': w,
    'sonnet_pct_used': sn,
    'weekly_deficit': w > 100,
    'last_updated': datetime.datetime.utcnow().isoformat()
}
with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False)
print(f'Updated: session={s}%, weekly={w}%, sonnet={sn}%')
" "<session%>" "<weekly%>" "<sonnet%>"
```

After writing, show the full Status table so the user can confirm.

Example usage:
```
/xgh-token-window set 45 62 30
```

---

## reset

Delete `~/.xgh/budget.yaml` to mark state as unknown:

```bash
python3 -c "
import os
path = os.path.expanduser('~/.xgh/budget.yaml')
if os.path.exists(path):
    os.remove(path)
    print('Budget state cleared — marked as unknown.')
else:
    print('Already unknown (no budget.yaml found).')
"
```

---

## Rationalization Table

| If you see | Do this |
|------------|---------|
| budget.yaml missing | Show "unknown" message with set instructions |
| weekly_deficit: true | Always show DEFICIT level regardless of % |
| Any window > 95% | Show CRITICAL even if deficit is false |
| Multiple windows in different levels | Use worst level |
| yaml parse error | Treat as unknown, suggest reset |
