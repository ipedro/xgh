# Copilot Chat Instructions — xgh (eXtreme Go Horse)

> Full agent instructions are in [`AGENTS.md`](../AGENTS.md) at the repository root.

## Overview

xgh is a Bash/YAML/Markdown MCS tech pack — no compiled runtime. Work follows the Superpowers methodology: test-first, plan-driven, memory-first.

## Quick commands

```bash
# Run tests
bash tests/test-install.sh && bash tests/test-config.sh

# Dry-run installer (no external deps)
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```

See [`AGENTS.md`](../AGENTS.md) for the complete guide.
