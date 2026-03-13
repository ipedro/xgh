# CLAUDE.md — xgh (eXtreme Go Horse)

> **Primary instructions:** See [`AGENTS.md`](./AGENTS.md) for the complete guide to working on this repository — project overview, tech stack, file structure, development guidelines, test commands, implementation status, and the Superpowers methodology.

---

## Claude Code — Quick Reference

### Run tests

```bash
bash tests/test-install.sh
bash tests/test-config.sh
bash tests/test-techpack.sh
bash tests/test-uninstall.sh
```

### Dry-run the installer

```bash
XGH_DRY_RUN=1 XGH_LOCAL_PACK=. bash install.sh
```

### Implementation plans

All tasks are tracked with `- [ ]` checkboxes in `docs/plans/`. Work through them in order (Plan 2 → 3 → 4 → 5 → 6). Mark steps complete with `- [x]` as you finish them.

### Slash commands available in this repo

After installing xgh into this project with `XGH_LOCAL_PACK=. bash install.sh`, the following commands become available:

- `/xgh-setup` — interactive MCP configuration

### Memory usage

If Cipher MCP is configured in this project, use it proactively:
- `cipher_memory_search` before starting any task
- `cipher_extract_and_operate_memory` after completing significant work
- `cipher_store_reasoning_memory` when making non-trivial architectural decisions

Refer to [`AGENTS.md`](./AGENTS.md) for the full decision protocol table.
