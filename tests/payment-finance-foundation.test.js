const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20261115220000_payment_intent_webhook_foundation.sql'), 'utf8');
const postgresFixture = fs.readFileSync(path.join(__dirname, 'payment-finance-foundation-postgres.test.sql'), 'utf8');

test('payment and finance storage is private, RLS-enabled and not directly browser writable', () => {
  for (const table of ['payment_intents', 'payment_transactions', 'provider_webhook_events', 'finance_accounts', 'finance_journals', 'finance_journal_lines', 'payment_currency_minor_units']) {
    assert.match(migration, new RegExp('create table private\\.' + table + '\\b', 'i'));
    assert.match(migration, new RegExp('alter table private\\.' + table + ' enable row level security', 'i'));
  }
  assert.match(migration, /revoke all on private\.[\s\S]*from public,anon,authenticated/i);
  assert.doesNotMatch(migration, /grant\s+(?:select|insert|update|delete|all)[\s\S]{0,120}private\.(?:payment_intents|payment_transactions|provider_webhook_events|finance_journals)/i);
});

test('payment intents enforce active buyer, accepted order, idempotency and supported minor-unit precision', () => {
  assert.match(migration, /p\.role='buyer' and p\.account_status='active'/i);
  assert.match(migration, /order_status not in \('accepted','ready_for_confirmation'\)/i);
  assert.match(migration, /Order already has a captured payment/i);
  assert.match(migration, /pg_advisory_xact_lock/i);
  assert.match(migration, /unique \(buyer_id,idempotency_key\)/i);
  assert.match(migration, /pg_advisory_xact_lock\(hashtext\(v_user::text/i);
  assert.match(migration, /payment_currency_minor_units/i);
  assert.match(migration, /currency is not enabled for payment/i);
  assert.match(migration, /v_order\.grand_total/i);
  assert.doesNotMatch(migration, /v_order\.total_price/i);
});

test('provider events are service-role only, deduplicated and fail closed on amount/currency or state mismatch', () => {
  assert.match(migration, /unique\(provider_code,provider_event_id\)/i);
  assert.match(migration, /signature_verified boolean not null default true check \(signature_verified\)/i);
  assert.match(migration, /coalesce\(auth\.role\(\),'\'\)\s*<>\s*'service_role'/i);
  assert.match(migration, /on conflict\(provider_code,provider_event_id\) do nothing/i);
  assert.match(migration, /processing_status<>'unmatched'/i);
  assert.match(migration, /provider_transaction_ref text not null/i);
  assert.match(migration, /capture_after_intent_expiry/i);
  assert.match(migration, /public\.expire_stale_payment_intents/i);
  assert.match(migration, /amount_or_currency_mismatch/i);
  assert.match(migration, /late_or_exception_capture/i);
  assert.match(migration, /additional_capture_for_captured_intent/i);
  assert.match(migration, /provider_transaction_reference_reused/i);
  assert.match(migration, /capture_after_intent_expiry/i);
  assert.match(migration, /public\.expire_stale_payment_intents/i);
  assert.match(migration, /grant execute on function public\.ingest_verified_payment_event[\s\S]*to service_role/i);
});

test('double-entry journals validate balance and preserve posted entries with reversal records', () => {
  assert.match(migration, /v_debits<>v_credits/i);
  assert.match(migration, /finance_journals_immutable/i);
  assert.match(migration, /finance_journal_lines_immutable/i);
  assert.match(migration, /before insert or update or delete on private\.finance_journal_lines/i);
  assert.match(migration, /posted finance journals are immutable/i);
  assert.match(migration, /public\.reverse_finance_journal/i);
  assert.match(migration, /reversal_of=p_original_journal_id/i);
  assert.match(migration, /grant execute on function public\.post_finance_journal[\s\S]*to service_role/i);
});


test('payment PostgreSQL fixture models the canonical total_price order contract', () => {
  assert.match(postgresFixture, /grand_total numeric\(18,2\) generated always as/i);
  assert.match(postgresFixture, /source_offer_total numeric\(18,2\)/i);
  assert.match(postgresFixture, /delivery_charge numeric\(18,2\)/i);
  assert.match(postgresFixture, /order_code,quantity,unit_price,currency,order_status,delivery_charge,source_offer_total/i);
  assert.match(postgresFixture, /payment-intent-key-0005/i);
});
