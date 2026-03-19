# Review: Context-Mode Enforcement Plan vs Spec

**Date:** 2026-03-18
**Status:** Reviewed

---

## 1. Spec Coverage

All four layers from the spec are present in the plan. The file inventory matches. One gap:

- **Missing:** The spec says heavy skills (investigate, implement, deep-retrieve, retrieve, analyze) should "additionally reference the full doc for phase-specific guidance in their own context-mode section." The plan (Task 9) applies only the generic 4-line preamble to all 23 skills -- no extended section for heavy skills. This is a **spec deviation (Important)**.

---

## 2. Critical Code Issues

### BLOCKER: Hash mismatch between spec claim and reality

The spec (line 171) claims `echo "$path" | shasum` equals Python's `hashlib.sha1(path.encode()).hexdigest()[:8]`. This is **false** -- `echo` appends a newline, producing different hashes:

```
bash:   echo "/Users/pedro/Developer/xgh" | shasum  -> 8571b1ff
python: hashlib.sha1(b"/Users/pedro/Developer/xgh") -> f1170937
```

The plan uses only Python heredocs (not bash `shasum`), so all hooks will be internally consistent. But the spec's bash example is wrong. If the session-start hook ever moves to bash, it will break. **Fix the spec**, not the plan.

### IMPORTANT: Nudge trigger condition inconsistency (spec vs plan)

- Spec (line 238): `ctx_calls == 0` AND `unedited >= 3`
- Plan (Task 8, line 748): `ctx_calls < 2` AND `unedited >= 3`
- Plan tests (line 332): test uses `ctx_calls=0`, passes with `< 2` logic

The plan is more lenient (fires nudge when ctx_calls is 0 or 1). The spec is stricter (only fires when ctx_calls is exactly 0). Both work, but the plan deviates. The plan's approach is arguably better (1 ctx call is not enough to suppress), but should be acknowledged.

### IMPORTANT: PostToolUse hooks produce no stdout

`post-edit.sh` and `post-ctx-call.sh` write no JSON output. PostToolUse hooks in Claude Code may expect output. The plan does not address this. The existing hooks (session-start, prompt-submit) all produce JSON. If Claude Code treats empty stdout as an error, these hooks will fail silently. **Verify Claude Code's PostToolUse contract** -- if output is required, add `echo '{}'`.

### IMPORTANT: `hook_input` JSON path may be wrong

The plan accesses `hook_input.get("tool_input", {}).get("file_path", "")`. Claude Code's actual stdin schema for PreToolUse/PostToolUse hooks may differ (e.g., `toolInput` vs `tool_input`, or nested differently). The plan does not reference any documentation for the stdin schema. If the key path is wrong, file tracking (`files_read`) will silently never populate, degrading tier-2/3 warning quality. **Verify against Claude Code docs**.

---

## 3. Test Coverage Assessment

**Covered well:**
- All three escalation tiers (0-2, 3-4, 5+)
- Suppression when `ctx_calls >= 2`
- Missing state file graceful handling
- Counter increments for reads, edits, ctx_calls
- Session-start new keys (`ctxModeAvailable`, decision table, deep-retrieve)
- Prompt-submit nudge firing and suppression

**Missing tests (Important):**
- No test for `ctxModeAvailable = false` (when context-mode is not installed)
- No test for file-path tracking in `files_read` (read a file, edit it, verify removal)
- No test for `post-edit` actually removing a file from `files_read`
- No worktree isolation test (spec calls for it)
- No test that session-start initializes the state file

**Missing tests (Suggestions):**
- No test for the routing reference doc content
- No test that the skill preamble was correctly inserted (plan says "spot-check" manually)

---

## 4. Task Ordering and Dependencies

The ordering is correct. Tasks 4-6 (new hooks) can be parallelized -- they are independent. Task 7 (session-start) depends on understanding the state file format but not on Tasks 4-6 existing. Task 8 (prompt-submit) is likewise independent until Task 11 integration.

Task 3 (write all failing tests) before Tasks 4-8 is correct TDD. However, `assert_file_exists` at the top of the new test block will cause early failures that prevent subsequent tests from running, since the test file uses `set -euo pipefail`. The `assert_file_exists` function only increments FAIL -- it does not exit -- so this is fine. But the test helper `run_hook_with_state` will fail hard when the hook script does not exist (bash will error on a missing file). **The Step 2 expectation "all new tests FAIL" is wrong** -- the test will crash at the first `run_hook_with_state` call, not neatly fail each assertion.

---

## 5. Missing Steps

1. **No installer dry-run test after Task 1** (hook path fix). The plan verifies manually but does not add a regression test to `test-install.sh`.

2. **No `plugin/references/` in installer copy logic.** The routing doc is created but never installed. If xgh is installed via the pack, the `plugin/references/` directory may not be copied to the target project. Verify that the installer handles this, or the skill preamble's reference to `plugin/references/context-mode-routing.md` will be a dead link.

3. **State file cleanup.** The spec mentions OS-managed `/tmp/` cleanup, but there is no explicit cleanup in session-start. If a user runs many sessions, old state files accumulate. This is fine (OS handles it), but worth noting.

---

## 6. TDD Compliance

Tasks 4-8 follow write-test, fail, implement, pass, commit. Task 1 (installer fix) does not follow TDD -- it fixes the bug without adding a test first. Task 2 (routing doc) is documentation, TDD not applicable. Task 9 (skill preambles) has no tests. Task 10 (hooks-settings + installer) has no dedicated test -- relies on Task 11's integration pass.

---

## Summary

| Category | Item | Severity |
|----------|------|----------|
| Spec deviation | Heavy skills missing extended context-mode section | Important |
| Code bug | Hash mismatch in spec (not in plan code) | Important (spec fix) |
| Code bug | Nudge trigger `< 2` vs spec's `== 0` | Important (acknowledge) |
| Code gap | PostToolUse hooks produce no stdout | Important (verify) |
| Code gap | `tool_input` JSON path unverified | Important (verify) |
| Test gap | No test for `ctxModeAvailable = false` | Important |
| Test gap | No file-path removal test for post-edit | Important |
| Test gap | Failing tests will crash, not fail neatly | Important |
| Missing step | Routing doc not in installer copy logic | Important |
| Missing step | No regression test for Task 1 fix | Suggestion |
| Spec issue | Worktree isolation test mentioned but not in plan | Suggestion |
