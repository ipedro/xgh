---
name: xgh-trigger
description: Manage the xgh trigger engine — list triggers, test them, silence noisy ones, and view firing history.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh trigger`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-trigger — Trigger Engine Management

Run the `xgh:trigger` skill to manage the xgh trigger engine.

## Usage

```
/xgh-trigger list
/xgh-trigger test <name>
/xgh-trigger silence <name> <duration>
/xgh-trigger history <name>
```

## Sub-commands

### list

Show all triggers with their status, last firing time, and whether they're silenced.

Outputs a table with: Name, Source, Path, Level, Enabled, Last Fired, and Status.

### test <name>

Dry-run a trigger against the latest inbox item that would match its conditions.

Shows what would execute without actually running any actions. Useful for validating trigger logic before deployment.

### silence <name> <duration>

Suppress a trigger temporarily using durations like `30m`, `2h`, or `1d`.

Updates the trigger state to prevent firing until the silence period expires.

### history <name>

Show the last firing events for a trigger, including total fire count, current cooldown state, and recently fired items.

Helps diagnose trigger behavior and cooldown/backoff patterns.
