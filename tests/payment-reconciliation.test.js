const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20261115230000_payment_reconciliation_batch_queue.sql'), 'utf8');

test('reconciliation batches and rows are private, RLS-enabled and not browser-readable', () => {
  for (const table of ['payment_reconciliation_batches', 'payment_reconciliation_rows']) {
    assert.match(migration, new RegExp('create table private\\.' + table + '\\b', 'i'));
    assert.match(migration, new RegExp('alter table private\\.' + table + ' enable row level security', 'i'));
  }
  assert.match(migration, /revoke all on private\.payment_reconciliation_batches,private\.payment_reconciliation_rows\s+from public,anon,authenticated/i);
});

test('normalized provider statements are idempotent and reject statement-reference content changes', () => {
  assert.match(migration, /unique\(provider_code,statement_ref\)/i);
  assert.match(migration, /source_sha256<>p_source_sha256/i);
  assert.match(migration, /Statement reference was reused with different content/i);
  assert.match(migration, /pg_advisory_xact_lock\(hashtext\(p_provider_code\|\|':'\|\|p_statement_ref\)\)/i);
});

test('reconciliation detects unmatched, duplicate, amount, currency, state and event mismatches', () => {
  for (const status of ['unmatched_provider_transaction','duplicate_provider_transaction','amount_mismatch','currency_mismatch','state_mismatch','event_mismatch']) {
    assert.ok(migration.includes(status), `missing reconciliation state ${status}`);
  }
  assert.match(migration, /v_currency<>p_currency or v_transaction\.currency<>v_currency/i);
});

test('exception review is server-only and cannot alter payment capture or ledger state', () => {
  assert.match(migration, /public\.review_payment_reconciliation_exception/i);
  assert.match(migration, /public\.get_payment_reconciliation_batch/i);
  assert.match(migration, /grant execute on function public\.ingest_payment_reconciliation_batch[\s\S]*to service_role/i);
  assert.match(migration, /grant execute on function public\.review_payment_reconciliation_exception[\s\S]*to service_role/i);
  assert.doesNotMatch(migration, /update private\.payment_intents/i);
  assert.doesNotMatch(migration, /update private\.finance_journals/i);
});
