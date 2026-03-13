#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0

assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else echo "FAIL: expected '$2', got '$1' — $3"; FAIL=$((FAIL+1)); fi
}
assert_file_exists() {
  if [ -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 missing — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_not_exists() {
  if [ ! -f "$1" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 should not exist — $2"; FAIL=$((FAIL+1)); fi
}
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: $1 missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
  if echo "$1" | grep -q "$2" 2>/dev/null; then PASS=$((PASS+1)); else echo "FAIL: output missing '$2' — $3"; FAIL=$((FAIL+1)); fi
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT_SCRIPT="${REPO_ROOT}/scripts/context-tree.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

CT_DIR="${TMPDIR}/.xgh/context-tree"
mkdir -p "$CT_DIR"
cat > "${CT_DIR}/_manifest.json" <<'EOF'
{"version":1,"team":"integration-test","created":"2026-03-13T00:00:00Z","domains":[]}
EOF
export XGH_CONTEXT_TREE_DIR="$CT_DIR"

echo "=== Phase 1: Curate multiple knowledge files ==="

bash "$CT_SCRIPT" sync --action curate \
  --domain "backend" --topic "database" \
  --title "PostgreSQL Connection Pooling" \
  --tags "database,postgres,performance" \
  --keywords "connection-pool,pgbouncer" \
  --source "manual" --from-agent "claude-code" \
  --body "## Raw Concept
Use PgBouncer for connection pooling. Set pool_mode to transaction.
Max connections per pool: 20 for web servers, 5 for background workers.

## Facts
- category: convention
  fact: Always use PgBouncer, never direct connections in production"

bash "$CT_SCRIPT" sync --action curate \
  --domain "backend" --topic "database" \
  --title "Database Migration Strategy" \
  --tags "database,migrations" \
  --keywords "migrations,schema,versioning" \
  --source "auto-curate" --from-agent "claude-code" \
  --body "## Raw Concept
Use sequential migration files. Never modify existing migrations.
Always test rollback before deploying."

bash "$CT_SCRIPT" sync --action curate \
  --domain "frontend" --topic "react" \
  --title "React State Management" \
  --tags "frontend,react,state" \
  --keywords "state,zustand,context" \
  --source "manual" --from-agent "claude-code" \
  --body "## Raw Concept
Use Zustand for global state. React Context for theme/locale only.
Never put server cache in Zustand — use React Query instead."

bash "$CT_SCRIPT" sync --action curate \
  --domain "devops" --topic "ci-cd" \
  --title "CI Pipeline Conventions" \
  --tags "devops,ci,github-actions" \
  --keywords "ci,pipeline,github-actions" \
  --source "auto-curate" --from-agent "claude-code" \
  --body "Run lint, test, build in parallel. Deploy only from main branch."

assert_file_exists "${CT_DIR}/backend/database/postgresql-connection-pooling.md" "postgres file"
assert_file_exists "${CT_DIR}/backend/database/database-migration-strategy.md" "migration file"
assert_file_exists "${CT_DIR}/frontend/react/react-state-management.md" "react file"
assert_file_exists "${CT_DIR}/devops/ci-cd/ci-pipeline-conventions.md" "ci file"

echo "=== Phase 2: Verify manifest and indexes ==="

MANIFEST=$(cat "${CT_DIR}/_manifest.json")
assert_contains "$MANIFEST" "backend" "manifest has backend"
assert_contains "$MANIFEST" "frontend" "manifest has frontend"
assert_contains "$MANIFEST" "devops" "manifest has devops"

assert_file_exists "${CT_DIR}/backend/_index.md" "backend index"
assert_file_exists "${CT_DIR}/frontend/_index.md" "frontend index"
assert_file_exists "${CT_DIR}/devops/_index.md" "devops index"

echo "=== Phase 3: Search ==="

RESULT=$(bash "$CT_SCRIPT" search --query "PostgreSQL connection pooling PgBouncer")
assert_contains "$RESULT" "postgresql-connection-pooling" "search finds postgres file"

RESULT2=$(bash "$CT_SCRIPT" search --query "React state management Zustand")
assert_contains "$RESULT2" "react-state-management" "search finds react file"

echo "=== Phase 4: Read + importance bumps ==="

bash "$CT_SCRIPT" read --path "backend/database/postgresql-connection-pooling" > /dev/null
bash "$CT_SCRIPT" read --path "backend/database/postgresql-connection-pooling" > /dev/null
bash "$CT_SCRIPT" read --path "backend/database/postgresql-connection-pooling" > /dev/null

PG_FILE="${CT_DIR}/backend/database/postgresql-connection-pooling.md"
IMP=$(grep "^importance:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$IMP" "29" "importance after manual curate + 3 reads"

ACCESS=$(grep "^accessCount:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$ACCESS" "3" "accessCount after 3 reads"

echo "=== Phase 5: Update ==="

bash "$CT_SCRIPT" update \
  --path "backend/database/postgresql-connection-pooling" \
  --body "## Raw Concept
Use PgBouncer for connection pooling. Set pool_mode to transaction.
Max connections: 20 for web, 5 for workers. Updated: Add health checks.

## Facts
- category: convention
  fact: Always use PgBouncer with health check endpoint"

IMP2=$(grep "^importance:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$IMP2" "34" "importance after update"

echo "=== Phase 6: Scoring + maturity promotion ==="

sed -i '' 's/importance: 34/importance: 65/' "$PG_FILE" 2>/dev/null || \
  sed -i 's/importance: 34/importance: 65/' "$PG_FILE"

bash "$CT_SCRIPT" sync --action score
MAT=$(grep "^maturity:" "$PG_FILE" | head -1 | awk '{print $2}')
assert_eq "$MAT" "validated" "promoted to validated at importance 65"

echo "=== Phase 7: Archive ==="

CI_FILE="${CT_DIR}/devops/ci-cd/ci-pipeline-conventions.md"
sed -i '' 's/importance: 10/importance: 5/' "$CI_FILE" 2>/dev/null || \
  sed -i 's/importance: 10/importance: 5/' "$CI_FILE"

bash "$CT_SCRIPT" sync --action archive
assert_file_not_exists "$CI_FILE" "CI file archived"
assert_file_exists "${CT_DIR}/devops/ci-cd/ci-pipeline-conventions.stub.md" "CI stub exists"
assert_file_exists "${CT_DIR}/_archived/devops/ci-cd/ci-pipeline-conventions.full.md" "CI full backup"

bash "$CT_SCRIPT" archive --restore "devops/ci-cd/ci-pipeline-conventions"
assert_file_exists "$CI_FILE" "CI file restored"

echo "=== Phase 8: List ==="

LIST=$(bash "$CT_SCRIPT" list)
assert_contains "$LIST" "postgresql-connection-pooling" "list shows postgres"
assert_contains "$LIST" "database-migration-strategy" "list shows migration"
assert_contains "$LIST" "react-state-management" "list shows react"

LIST_BE=$(bash "$CT_SCRIPT" list --domain "backend")
assert_contains "$LIST_BE" "postgresql" "filtered list has postgres"

echo "=== Phase 9: Delete ==="

bash "$CT_SCRIPT" delete --path "backend/database/database-migration-strategy"
assert_file_not_exists "${CT_DIR}/backend/database/database-migration-strategy.md" "deleted migration file"

echo ""
echo "=== Integration test: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
