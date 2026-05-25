#!/usr/bin/env bash
# post-migration.sh — backend-specific steps after a schema migration is applied locally.
#
# Called manually by the user (or invoked from /db-schema's Step 10).
# Only relevant if backend_db_type is configured. Projects without a backend
# don't have this script (or it just exits 0).
#
# Typical responsibilities:
#   1. Refresh backend caches that don't auto-reload on `migration up`
#      (e.g., PostgREST schema cache in some local stacks)
#   2. Regenerate typed bindings (so the typecheck doesn't fail on stale types)
#   3. Notify the live backend (managed Postgres / Supabase / etc.) if needed

set -euo pipefail

# Ensure brew-installed tools (jq, etc.) are on PATH even in non-interactive
# shells where ~/.zprofile isn't loaded. macOS Apple Silicon path comes first.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────
# CUSTOMIZE: per-backend post-migration steps
# ─────────────────────────────────────────────────────────────────────

# Example 1 — Supabase (local Docker stack):
# docker compose -f supabase/docker-compose.yml restart postgrest \
#   || echo "warning: PostgREST restart failed; new RPCs may not appear in schema cache"
# supabase gen types typescript --local > src/lib/supabase/types.ts \
#   || echo "warning: type regeneration failed"

# Example 2 — Prisma:
# npx prisma migrate dev --skip-seed
# npx prisma generate

# Example 3 — Drizzle:
# npx drizzle-kit push
# # types regen happens automatically with drizzle-kit

# Example 4 — Raw Postgres + pgtyped:
# psql "$DATABASE_URL" -f "$(ls -t supabase/migrations/*.sql | head -1)"
# npx pgtyped -c pgtyped.config.json

# Example 5 — Django:
# python manage.py migrate
# python manage.py inspectdb > types.py  # if using inspectdb workflow

# Example 6 — None (no backend / no codegen step):
# exit 0

# ─────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────
echo "ℹ️  post-migration.sh has no commands configured."
echo "    Edit .harness/scripts/post-migration.sh to add your backend's"
echo "    cache-refresh + typed-bindings-regenerate steps."
echo ""
echo "    Without this, Stage 4 (/execution-plan) may operate on stale types."

exit 0
