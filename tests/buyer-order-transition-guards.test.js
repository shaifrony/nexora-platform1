const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function readMigration(name) {
  return fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', name), 'utf8');
}

function readFunction(source, signature) {
  const start = source.toLowerCase().indexOf(signature.toLowerCase());
  assert.ok(start >= 0, `Missing expected function: ${signature}`);
  const end = source.indexOf('\n$$;', start);
  assert.ok(end > start, `Could not isolate function body: ${signature}`);
  return source.slice(start, end);
}

const productOrders = readMigration('20261114150000_product_inventory_moq_quantity_pricing.sql');
const demandOrders = readMigration('20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql');
const productTransition = readFunction(productOrders, 'create or replace function private.transition_commerce_order(');
const demandTransition = readFunction(demandOrders, 'create or replace function private.transition_buyer_demand_order(');

test('Product and Service order transitions enforce assigned active Buyer/Seller identity', () => {
  assert.match(productTransition, /v_actor uuid := auth\.uid\(\)/i);
  assert.match(productTransition, /if v_actor is null then raise exception 'Login required'/i);
  assert.match(productTransition, /select \* into v_order from public\.commerce_orders where id=p_order_id for update/i);
  assert.match(productTransition, /p\.id=v_actor and p\.account_status='active'[\s\S]*?p\.role='buyer' and p\.id=v_order\.buyer_id[\s\S]*?p\.role='seller' and p\.id=v_order\.seller_id/i);
});

test('Product and Service order state machine restricts every action to its permitted actor and prior state', () => {
  const guards = [
    /p_action='accept'[\s\S]*?v_actor<>v_order\.seller_id or v_order\.order_status<>'pending'[\s\S]*?v_next:='accepted'/i,
    /p_action='ready'[\s\S]*?v_actor<>v_order\.seller_id or v_order\.order_status<>'accepted'[\s\S]*?v_next:='ready_for_confirmation'/i,
    /p_action='complete'[\s\S]*?v_actor<>v_order\.buyer_id or v_order\.order_status<>'ready_for_confirmation'[\s\S]*?v_next:='completed'/i,
    /p_action='cancel'[\s\S]*?v_actor<>v_order\.buyer_id or v_order\.order_status<>'pending'[\s\S]*?v_next:='cancelled'/i,
    /p_action='reject'[\s\S]*?v_actor<>v_order\.seller_id or v_order\.order_status<>'pending'[\s\S]*?length\(btrim\(coalesce\(p_note,''\)\)\) < 5[\s\S]*?v_next:='rejected'/i,
  ];
  for (const guard of guards) assert.match(productTransition, guard);
  assert.match(productTransition, /else\s+raise exception 'Unsupported order action'/i);
});

test('Product inventory is deducted only on completion and released on cancellation or rejection', () => {
  assert.match(productTransition, /if v_next='completed'[\s\S]*?stock_quantity=stock_quantity-v_order\.quantity,[\s\S]*?reserved_quantity=reserved_quantity-v_order\.quantity/i);
  assert.match(productTransition, /elsif v_next in \('cancelled','rejected'\)[\s\S]*?reserved_quantity=reserved_quantity-v_order\.quantity/i);
  assert.match(productTransition, /if v_next='completed'[\s\S]*?insert into private\.review_purchase_eligibility/i);
});

test('Buyer Demand order transitions are isolated to Buyer Demand orders and enforce the same actor/state rules', () => {
  assert.match(demandTransition, /from public\.commerce_orders\s+where id=p_order_id and listing_type='buyer_demand' for update/i);
  assert.match(demandTransition, /p\.id=v_actor and p\.account_status='active'[\s\S]*?p\.role='buyer' and p\.id=v_order\.buyer_id[\s\S]*?p\.role='seller' and p\.id=v_order\.seller_id/i);
  const guards = [
    /p_action='accept'[\s\S]*?v_actor<>v_order\.seller_id or v_order\.order_status<>'pending'[\s\S]*?v_next:='accepted'/i,
    /p_action='ready'[\s\S]*?v_actor<>v_order\.seller_id or v_order\.order_status<>'accepted'[\s\S]*?v_next:='ready_for_confirmation'/i,
    /p_action='complete'[\s\S]*?v_actor<>v_order\.buyer_id or v_order\.order_status<>'ready_for_confirmation'[\s\S]*?v_next:='completed'/i,
    /p_action='cancel'[\s\S]*?v_actor<>v_order\.buyer_id or v_order\.order_status<>'pending'[\s\S]*?v_next:='cancelled'/i,
    /p_action='reject'[\s\S]*?v_actor<>v_order\.seller_id or v_order\.order_status<>'pending'[\s\S]*?length\(btrim\(coalesce\(p_note,''\)\)\)<5[\s\S]*?v_next:='rejected'/i,
  ];
  for (const guard of guards) assert.match(demandTransition, guard);
  assert.match(demandTransition, /else raise exception 'Unsupported order action'/i);
});

test('Both order transition RPCs are SECURITY DEFINER with an empty search_path', () => {
  assert.match(productTransition, /language plpgsql\s+security definer\s+set search_path=''/i);
  assert.match(demandTransition, /language plpgsql security definer set search_path=''/i);
});
