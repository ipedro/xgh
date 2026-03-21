#!/usr/bin/env bash
# Run all xgh skill and agent triggering tests
# Usage: ./run-all.sh [--skills-only | --agents-only]
#
# NOTE: This is an opt-in test suite — it invokes claude -p and costs API tokens.
# Do NOT call from tests/test-config.sh.
# Run manually when editing skill/agent trigger descriptions.
#
# Environment variables:
#   XGH_TEST_MODEL    — model to use (default: sonnet)
#   XGH_TEST_BUDGET   — max USD per test invocation (default: 0.50)
#   XGH_TEST_LOG_DIR  — persistent log directory (default: /tmp/xgh-test-logs)
#
# Cost estimate: ~18 prompts × 1 turn ≈ ~$0.90 per full suite run (sonnet).
#
# Logs are saved to $XGH_TEST_LOG_DIR (default /tmp/xgh-test-logs):
#   summary.log          — one-line-per-test results
#   skill-xgh--NAME/     — per-skill logs (claude-output.json, prompt.txt, result.txt)
#   agent-xgh--NAME/     — per-agent logs
#
# Examples:
#   ./run-all.sh                                    # run all 18 tests
#   ./run-all.sh --skills-only                      # run 10 skill tests
#   ./run-all.sh --agents-only                      # run 8 agent tests
#   XGH_TEST_MODEL=haiku ./run-all.sh               # cheaper run with haiku

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

FILTER="${1:-all}"   # --skills-only, --agents-only, or all (default)

export XGH_TEST_LOG_DIR="${XGH_TEST_LOG_DIR:-/tmp/xgh-test-logs}"
mkdir -p "$XGH_TEST_LOG_DIR"
SUMMARY_LOG="$XGH_TEST_LOG_DIR/summary.log"

# ── Skill tests ─────────────────────────────────────────────────────────────
# Format: "xgh:skill:prompt_file" — colon separates namespace:skill from filename
SKILL_TESTS=(
    "xgh:retrieve:retrieve.txt"
    "xgh:analyze:analyze.txt"
    "xgh:briefing:briefing.txt"
    "xgh:implement:implement.txt"
    "xgh:investigate:investigate.txt"
    "xgh:track:track.txt"
    "xgh:doctor:doctor.txt"
    "xgh:index:index.txt"
    "xgh:trigger:trigger.txt"
    "xgh:schedule:schedule.txt"
)

# ── Agent tests ─────────────────────────────────────────────────────────────
# Format: "xgh:agent-name:prompt_file" — uses run-agent-test.sh instead of run-test.sh
AGENT_TESTS=(
    "xgh:code-reviewer:agent-code-reviewer.txt"
    "xgh:collaboration-dispatcher:agent-collaboration-dispatcher.txt"
    "xgh:pipeline-doctor:agent-pipeline-doctor.txt"
    "xgh:context-curator:agent-context-curator.txt"
    "xgh:investigation-lead:agent-investigation-lead.txt"
    "xgh:pr-reviewer:agent-pr-reviewer.txt"
    "xgh:retrieval-auditor:agent-retrieval-auditor.txt"
    "xgh:onboarding-guide:agent-onboarding-guide.txt"
)

echo "=== xgh Skill & Agent Triggering Test Suite ==="
echo "Plugin dir: $(cd "$SCRIPT_DIR/../.." && pwd)"
echo "Model:  ${XGH_TEST_MODEL:-sonnet}"
echo "Filter: $FILTER"
echo "Logs:   $XGH_TEST_LOG_DIR"
echo ""

# Start fresh summary log
echo "# xgh triggering test results — $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SUMMARY_LOG"
echo "# model=${XGH_TEST_MODEL:-sonnet} filter=$FILTER" >> "$SUMMARY_LOG"
echo "" >> "$SUMMARY_LOG"

PASSED=0
FAILED=0
RESULTS=()

run_skill_tests() {
    for entry in "${SKILL_TESTS[@]}"; do
        SKILL="${entry%:*}"
        PROMPT_FILE="${entry##*:}"
        FULL_PROMPT="$PROMPTS_DIR/$PROMPT_FILE"

        if [ ! -f "$FULL_PROMPT" ]; then
            echo "⚠️  SKIP: No prompt file for $SKILL ($FULL_PROMPT)"
            echo "SKIP [skill] $SKILL — missing prompt" >> "$SUMMARY_LOG"
            continue
        fi

        echo "--- Testing skill: $SKILL ---"

        if "$SCRIPT_DIR/run-test.sh" "$SKILL" "$FULL_PROMPT"; then
            PASSED=$((PASSED + 1))
            RESULTS+=("✅ [skill] $SKILL")
            echo "PASS [skill] $SKILL" >> "$SUMMARY_LOG"
        else
            FAILED=$((FAILED + 1))
            RESULTS+=("❌ [skill] $SKILL")
            echo "FAIL [skill] $SKILL" >> "$SUMMARY_LOG"
        fi

        echo ""
    done
}

run_agent_tests() {
    for entry in "${AGENT_TESTS[@]}"; do
        AGENT="${entry%:*}"
        PROMPT_FILE="${entry##*:}"
        FULL_PROMPT="$PROMPTS_DIR/$PROMPT_FILE"

        if [ ! -f "$FULL_PROMPT" ]; then
            echo "⚠️  SKIP: No prompt file for $AGENT ($FULL_PROMPT)"
            echo "SKIP [agent] $AGENT — missing prompt" >> "$SUMMARY_LOG"
            continue
        fi

        echo "--- Testing agent: $AGENT ---"

        if "$SCRIPT_DIR/run-agent-test.sh" "$AGENT" "$FULL_PROMPT"; then
            PASSED=$((PASSED + 1))
            RESULTS+=("✅ [agent] $AGENT")
            echo "PASS [agent] $AGENT" >> "$SUMMARY_LOG"
        else
            FAILED=$((FAILED + 1))
            RESULTS+=("❌ [agent] $AGENT")
            echo "FAIL [agent] $AGENT" >> "$SUMMARY_LOG"
        fi

        echo ""
    done
}

case "$FILTER" in
    --skills-only)
        run_skill_tests
        ;;
    --agents-only)
        run_agent_tests
        ;;
    *)
        run_skill_tests
        run_agent_tests
        ;;
esac

echo "=== Summary ==="
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "Passed: $PASSED / $((PASSED + FAILED))"
echo "Logs:   $XGH_TEST_LOG_DIR"
echo "Summary: $SUMMARY_LOG"

# Append totals to summary
echo "" >> "$SUMMARY_LOG"
echo "# total=$((PASSED + FAILED)) passed=$PASSED failed=$FAILED" >> "$SUMMARY_LOG"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
