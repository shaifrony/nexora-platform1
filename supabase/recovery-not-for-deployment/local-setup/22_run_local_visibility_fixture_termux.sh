#!/data/data/com.termux/files/usr/bin/bash
# NEXORA local-only visibility fixture runner for Termux.
# Runs only against the local PostgreSQL database nexora_test.
# It refuses to proceed if another connection to nexora_test is still open.
set -euo pipefail

DB="nexora_test"
BASE_URL="https://raw.githubusercontent.com/shaifrony/nexora-platform1/nexora-development/supabase/recovery-not-for-deployment/local-setup"
WORK_DIR="$HOME/nexora-local-visibility"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

for file in \
  19_cleanup_review_rpc_concurrency_fixture.sql \
  21_local_marketplace_visibility_fixture.sql \
  20_dual_market_visibility_read_only_verification.sql
do
  echo "Downloading $file ..."
  curl -fL "$BASE_URL/$file" -o "$file"
done

echo
echo "Preflight: checking local database and open sessions ..."
DB_NAME="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT current_database();")"
if [ "$DB_NAME" != "$DB" ]; then
  echo "STOP: connected database is '$DB_NAME', expected '$DB'."
  exit 1
fi

OTHER_SESSIONS="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();")"
if [ "$OTHER_SESSIONS" != "0" ]; then
  echo "STOP: $OTHER_SESSIONS other PostgreSQL session(s) are still connected to $DB."
  echo "Close every other psql session, then run this script again. No cleanup was performed."
  exit 1
fi

FOUNDATION_OK="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT to_regclass('public.profiles') IS NOT NULL AND to_regprocedure('auth.uid()') IS NOT NULL AND to_regprocedure('auth.jwt()') IS NOT NULL AND to_regprocedure('public.is_nexora_admin()') IS NOT NULL;")"
if [ "$FOUNDATION_OK" != "t" ]; then
  echo "STOP: local foundation objects are missing. No cleanup was performed."
  exit 1
fi

MARKETPLACE_OBJECTS="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT (to_regclass('public.products') IS NOT NULL)::int + (to_regclass('public.public_businesses') IS NOT NULL)::int + (to_regclass('public.business_profiles') IS NOT NULL)::int;")"
if [ "$MARKETPLACE_OBJECTS" != "0" ]; then
  echo "STOP: one or more Marketplace visibility objects already exist."
  echo "Inspect the database instead of rerunning the fixture. No cleanup was performed."
  exit 1
fi

echo "Preflight PASS. Cleaning only the known local concurrency fixture rows ..."
psql -X -d "$DB" -v ON_ERROR_STOP=1 -f 19_cleanup_review_rpc_concurrency_fixture.sql

echo
echo "Creating the limited local Marketplace visibility fixture ..."
psql -X -d "$DB" -v ON_ERROR_STOP=1 -f 21_local_marketplace_visibility_fixture.sql

echo
echo "Running read-only visibility verification ..."
psql -X -d "$DB" -v ON_ERROR_STOP=1 -f 20_dual_market_visibility_read_only_verification.sql

echo
echo "Runner finished. Review every PASS/FAIL/SKIP line above."
echo "This is a limited local schema/catalog check, not full Marketplace or hosted Supabase validation."
