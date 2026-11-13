#!/data/data/com.termux/files/usr/bin/bash
# NEXORA B-03 local fixture + audit + behavior test runner.
# SAFE TARGET: nexora_test only. No cleanup, no migration replay, no hosted access.
set -euo pipefail

DB="nexora_test"
WORK_DIR="$HOME/nexora-local-buyer-demand"
BASE="https://raw.githubusercontent.com/shaifrony/nexora-platform1"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Downloading immutable local-only SQL files ..."
curl -fL --retry 3 "$BASE/cf3dc4991cad964d664ecb47f031c72e19914114/supabase/recovery-not-for-deployment/local-setup/25_local_buyer_demand_fixture.sql" -o 25_local_buyer_demand_fixture.sql
curl -fL --retry 3 "$BASE/7c8bb362e082cbc76de22c6e9defac2198d6952b/supabase/recovery-not-for-deployment/local-setup/24_local_buyer_demand_privacy_audit.sql" -o 24_local_buyer_demand_privacy_audit.sql
curl -fL --retry 3 "$BASE/844304bbb79e8984fefdb9d3085997c78f69eab1/supabase/recovery-not-for-deployment/local-setup/26_local_buyer_demand_behavior_tests.sql" -o 26_local_buyer_demand_behavior_tests.sql
curl -fL --retry 3 "$BASE/0e6d1ccdc9277b6210ab3887d103f3497a836fab/supabase/recovery-not-for-deployment/local-setup/28_local_buyer_demand_policy_dependency_patch.sql" -o 28_local_buyer_demand_policy_dependency_patch.sql

echo
echo "Preflight: verifying local target and prerequisites ..."
DB_NAME="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT current_database();")"
if [ "$DB_NAME" != "$DB" ]; then
  echo "STOP: connected database is '$DB_NAME', expected '$DB'."
  exit 1
fi

FOUNDATION_OK="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT to_regclass('public.profiles') IS NOT NULL AND to_regprocedure('auth.uid()') IS NOT NULL AND to_regprocedure('public.is_nexora_admin()') IS NOT NULL;")"
if [ "$FOUNDATION_OK" != "t" ]; then
  echo "STOP: local foundation fixture 06 is missing. No SQL was executed."
  exit 1
fi

VISIBILITY_OK="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT to_regclass('public.products') IS NOT NULL AND to_regclass('public.public_businesses') IS NOT NULL;")"
if [ "$VISIBILITY_OK" != "t" ]; then
  echo "STOP: Marketplace visibility fixture 21 is missing. No SQL was executed."
  exit 1
fi

DEMAND_OBJECTS="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT (to_regclass('public.buyer_demands') IS NOT NULL)::int + (to_regclass('public.seller_offers') IS NOT NULL)::int + (to_regclass('public.buyer_demand_inbox') IS NOT NULL)::int + (to_regclass('public.public_buyer_demands') IS NOT NULL)::int;")"
if [ "$DEMAND_OBJECTS" != "0" ] && [ "$DEMAND_OBJECTS" != "4" ]; then
  echo "STOP: partial Demand fixture detected ($DEMAND_OBJECTS of 4 objects). Inspect manually; no SQL was executed."
  exit 1
fi

OPEN_SESSIONS="$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -Atqc "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid();")"
if [ "$OPEN_SESSIONS" != "0" ]; then
  echo "STOP: $OPEN_SESSIONS other PostgreSQL session(s) are connected to $DB."
  echo "Close other psql sessions with \q, then rerun. No SQL was executed."
  exit 1
fi

echo "Preflight PASS."
if [ "$DEMAND_OBJECTS" = "0" ]; then
  echo "Creating only the local Buyer Demand fixture ..."
  psql -X -d "$DB" -v ON_ERROR_STOP=1 -f 25_local_buyer_demand_fixture.sql
else
  echo "Existing complete local Demand fixture detected; skipping fixture creation."
fi

echo
echo "Applying narrow local policy dependency repair (seller_id remains private) ..."
psql -X -d "$DB" -v ON_ERROR_STOP=1 -f 28_local_buyer_demand_policy_dependency_patch.sql

echo
echo "Running read-only privacy / RLS / routing catalog audit ..."
psql -X -d "$DB" -v ON_ERROR_STOP=1 -f 24_local_buyer_demand_privacy_audit.sql

echo
echo "Running local Buyer ownership, public privacy, Seller Inbox, routing and quotation behavior tests ..."
psql -X -d "$DB" -v ON_ERROR_STOP=1 -f 26_local_buyer_demand_behavior_tests.sql

echo
echo "All runner steps completed. Review each PASS/FAIL/SKIP line above."
echo "This is a reconstructed local PostgreSQL fixture, not hosted Supabase/JWT/PostgREST or browser E2E validation."
