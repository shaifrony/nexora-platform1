# NEXORA Review RPC — two-session concurrency procedure

**Local-only target:** \`nexora_test\`  
**Prerequisites:** local fixture 06, RPC prototype 12, original RPC tests 13, extended tests 15 all completed.  
**Never run against hosted/production Supabase.**

## A. Prepare fixture (one time)

Run \`17_prepare_review_rpc_concurrency_fixture.sql\` in one Termux session. It creates two dedicated test users, an authorized reviewer, and one pending Buyer-to-Seller request. Unlike rollback-based tests, this fixture is committed so two independent sessions can see it. Clean it up after the test with script 19.

## B. Session A — hold the first successful review open

Open Termux session A and run:

\`\`\`sh
psql -d nexora_test
\`\`\`

At the psql prompt, paste these statements **one at a time**:

\`\`\`sql
BEGIN;
SELECT set_config('request.jwt.claim.sub','22000000-0000-4000-8000-000000000001',true);
SELECT public.rpc_review_role_request(
  '32000000-0000-4000-8000-000000000001',
  'approved',
  'Concurrency test — session A'
);
\`\`\`

Do **not** COMMIT yet. Leave Session A open. The successful function call should return, but its transaction keeps the request-row lock until COMMIT/ROLLBACK.

## C. Session B — attempt the same review

Open a second independent Termux session and run:

\`\`\`sh
psql -d nexora_test
\`\`\`

At the psql prompt, paste these statements **one at a time**:

\`\`\`sql
BEGIN;
SELECT set_config('request.jwt.claim.sub','22000000-0000-4000-8000-000000000001',true);
SELECT public.rpc_review_role_request(
  '32000000-0000-4000-8000-000000000001',
  'approved',
  'Concurrency test — session B'
);
\`\`\`

The final RPC call should wait because Session A still holds the row lock. This is expected PostgreSQL row-lock behavior.

## D. Release Session A

Return to Session A and run:

\`\`\`sql
COMMIT;
\`\`\`

Now Session B should resume and return SQLSTATE \`55000\` with a message that the request is no longer pending. Because the statement failed, finish Session B with:

\`\`\`sql
ROLLBACK;
\`\`\`

If Session B returns before Session A commits, the test did not demonstrate the intended blocking sequence.

## E. Verify the final state (either psql session)

Run:

\`\`\`sql
SELECT id, status, reviewed_by, reviewed_at, admin_note
FROM public.role_requests
WHERE id='32000000-0000-4000-8000-000000000001';

SELECT count(*) AS matching_audit_rows
FROM public.admin_audit_logs
WHERE target_id='32000000-0000-4000-8000-000000000001';
\`\`\`

Expected:
- request status = \`approved\`;
- reviewed_by = reviewer UID \`22000000-0000-4000-8000-000000000001\`;
- admin_note belongs to Session A;
- exactly one matching audit row.

Then exit both psql sessions with \`\\q\`.

## F. Cleanup

Run \`19_cleanup_review_rpc_concurrency_fixture.sql\` once, after both sessions are closed. It removes only the dedicated test request, its matching audit rows, and the two dedicated auth identities. Verify it prints \`CLEANED\`.

## Interpretation

A successful result demonstrates local PostgreSQL row-lock and single-winner behavior for this local prototype only. It does not validate hosted Supabase Auth/JWT, RLS, PostgREST, private-schema exposure, MFA/AAL2, or production deployment readiness.
