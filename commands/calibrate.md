---
name: xgh-calibrate
description: Calibrate the dedup similarity threshold by evaluating real memory pairs. Supports interactive, headless, and comparison modes with F1 scoring.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh calibrate`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-calibrate — Dedup Threshold Calibration

Run the `xgh:calibrate` skill to tune the dedup threshold for your embedding model.

## Usage

```
/xgh-calibrate
/xgh-calibrate --auto
/xgh-calibrate --compare
```

- (no flag) — interactive mode: you judge each pair
- `--auto` — headless mode: Claude judges, auto-updates if confidence > 90%
- `--compare` — runs both and shows AI vs human agreement rate
