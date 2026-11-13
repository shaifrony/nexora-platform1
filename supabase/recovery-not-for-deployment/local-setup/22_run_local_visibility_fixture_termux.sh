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
  curl -fL --retry 3 -H "Cache-Control: no-cache" "$BASE_URL/$file?fresh=20261113-plain-sql-04746bf0" -o "$file"
  if [ "$file" = "19_cleanup_review_rpc_concurrency_fixture.sql" ]; then
    # Strip legacy psql meta-command lines even if a stale CDN copy is served.
    # ON_ERROR_STOP is already supplied by the psql command below.
    sed -i '/set ON_ERROR_STOP on/d; /pset pager off/d' "$file"
    if grep -nE 'set ON_ERROR_STOP on|pset pager off' "$file"; then
      echo "STOP: could not remove legacy psql meta-command lines."
      echo "No SQL has been executed."
      exit 1
    fi
    GRANT_LINE="$(grep -n "^DELETE FROM public.admin_permission_grants$" "$file" | cut -d: -f1 || true)"
    STAFF_LINE="$(grep -n "^DELETE FROM public.admin_staff$" "$file" | cut -d: -f1 || true)"
    USERS_LINE="$(grep -n "^DELETE FROM auth.users$" "$file" | cut -d: -f1 || true)"
    if [ -z "$GRANT_LINE" ] || [ -z "$STAFF_LINE" ] || [ -z "$USERS_LINE" ] ||
       [ "$GRANT_LINE" -ge "$STAFF_LINE" ] || [ "$STAFF_LINE" -ge "$USERS_LINE" ]; then
      echo "STOP: downloaded cleanup SQL is stale or its FK delete order is unsafe."
      echo "Expected admin_permission_grants -> admin_staff -> auth.users."
      echo "No SQL has been executed."
      exit 1
    fi
    if grep -nE '^\\\\(set|pset)' "$file"; then
      echo "STOP: cleanup SQL should contain no psql meta-commands."
      echo "No SQL has been executed."
      exit 1
    fi
    echo "Verified cleanup DELETE order; psql error handling is supplied by the runner:"
    grep -n "^DELETE FROM" "$file"
  fi
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
