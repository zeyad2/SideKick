#!/usr/bin/env bash
# Migration-applies + RLS test against a throwaway Postgres (Docker).
# Usage: bash scripts/test_migration.sh
set -euo pipefail

CT=sidekick_migtest
IMG=postgres:16-alpine
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() { docker rm -f "$CT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "== starting throwaway postgres =="
docker run -d --name "$CT" -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=sidekick "$IMG" >/dev/null

echo "== waiting for readiness =="
for i in $(seq 1 30); do
  if docker exec "$CT" pg_isready -U postgres -d sidekick >/dev/null 2>&1; then break; fi
  sleep 1
done

run() { # run <file>
  docker exec -i "$CT" psql -v ON_ERROR_STOP=1 -U postgres -d sidekick < "$1"
}

echo "== 1/4 bootstrap auth stubs =="
run "$ROOT/supabase/tests/00_bootstrap_auth.sql"

echo "== 2/4 apply migration =="
run "$ROOT/supabase/migrations/0001_initial_schema.sql"
echo "   migration applied cleanly."

echo "== 3/4 RLS isolation test =="
run "$ROOT/supabase/tests/10_rls_isolation.sql"

echo "== 4/4 FK ownership + domain CHECK test =="
run "$ROOT/supabase/tests/20_fk_ownership.sql"

echo ""
echo "ALL CHECKS PASSED (clean apply + RLS isolation + FK ownership + CHECKs)."
