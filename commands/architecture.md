---
name: xgh-architecture
description: "Analyze codebase architecture — module boundaries, dependency graph, critical paths, public surfaces"
allowed-tools: Bash, Read, Glob, Grep, Agent
---

> **Output format:** Follow the [xgh output style guide](../templates/output-style.md). Start with `## 🐴🤖 xgh architecture`. Use markdown tables for structured data. End with an italicized next step.

# /xgh-architecture — Codebase Architecture Analysis

Run the `xgh:architecture` skill to analyze the codebase architecture.

## Usage

```
/xgh-architecture [quick|full]
```

- `quick` (default): module boundaries, public surfaces, integration points
- `full`: adds dependency graph, critical paths, and test landscape

`ARGUMENTS: $ARGUMENTS`
