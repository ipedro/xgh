---
name: xgh-doctor
description: Validate the full xgh ingest pipeline — config, connectivity, scheduler freshness, and workspace stats.
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh doctor`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-doctor — Pipeline Health Check

Run the `xgh:doctor` skill to validate the full ingest pipeline.

## Usage

```
/xgh-doctor
```

Outputs a structured ✓/✗ report with specific fix suggestions for any failures.
