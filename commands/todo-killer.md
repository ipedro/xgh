# /xgh-todo-killer

Scan and fix TODO/FIXME/HACK/DEPRECATED comments. Populates `.xgh/patterns.yaml` with migration signals and fixes resolvable items highest-impact first.

## Usage

```
/xgh-todo-killer                          # scan + fix everything
/xgh-todo-killer --mode scan              # harvest signals only, no code changes
/xgh-todo-killer --mode fix               # fix only, skip patterns.yaml update
/xgh-todo-killer --filter FIXME           # only FIXME comments
/xgh-todo-killer --glob "Sources/**"      # scope to directory
/xgh-todo-killer --priority high          # only high-priority clusters
/xgh-todo-killer --dry-run                # preview without changes
```

Run the `xgh:todo-killer` skill.
