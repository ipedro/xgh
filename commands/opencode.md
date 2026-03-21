---
name: opencode
description: "Dispatch tasks to OpenCode CLI for parallel implementation or code review"
usage: "/xgh-opencode [exec|review] <prompt>"
aliases: ["oc"]
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh opencode`. Use markdown tables for structured data. Use ✅ ⚠️ ❌ for status. End with an italicized next step.

# /xgh-opencode

Run the `xgh:opencode` skill to dispatch implementation tasks or code reviews to OpenCode CLI.

## Usage

```
/xgh-opencode exec "Add unit tests for the auth module"
/xgh-opencode review "Focus on error handling"
/xgh-opencode exec --model anthropic/claude-opus-4-6 "Refactor connection pooling"
/xgh-opencode exec --same-dir "Fix lint warnings in src/utils/"
```
