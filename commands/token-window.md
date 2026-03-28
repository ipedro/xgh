---
name: xgh-token-window
description: Check token budget state and get recommendations based on current window usage
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh token-window`. Use 🟢 🟡 🔴 🚨 for budget status.

# /xgh-token-window — Token Budget Visibility

Run the `xgh:token-window` skill to check current session/weekly/Sonnet window consumption and receive budget-aware recommendations.

## Usage

```
/xgh-token-window                                     # full status table
/xgh-token-window --warn                              # only show if budget is tight
/xgh-token-window --status                            # one-line for pasting in command-center
/xgh-token-window set <session%> <weekly%> <sonnet%>  # update from CodexBar screenshot
/xgh-token-window reset                               # mark budget as unknown
```

## Examples

```
/xgh-token-window set 45 62 30
→ Updates ~/.xgh/budget.yaml and shows current status table

/xgh-token-window --status
→ Token: Session 45% 🟡 | Weekly 62% 🟡 | Sonnet 30% 🟢 — NORMAL

/xgh-token-window --warn
→ (silent if FRESH/NORMAL, shows warning if TIGHT/CRITICAL/DEFICIT)
```
