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

const directOrders = readMigration('20261114150000_product_inventory_moq_quantity_pricing.sql');
const productNegotiations = readMigration('20261115110000_product_price_negotiation.sql');
const demandNegotiations = readMigration('20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql');

test('Commerce Order writer inventory covers all three independent creation paths', () => {
  const writers = [
    {
      name: 'direct Product/Service orders',
      body: readFunction(directOrders, 'create or replace function private.create_commerce_order('),
    },
    {
      name: 'mutually accepted Product Price Negotiation',
      body: readFunction(productNegotiations, 'create or replace function private.respond_to_product_price_negotiation('),
    },
    {
      name: 'Buyer Demand quotation conversion',
      body: readFunction(demandNegotiations, 'create or replace function private.respond_to_demand_offer('),
    },
  ];

  for (const writer of writers) {
    assert.match(writer.body, /insert\s+into\s+public\.commerce_orders\s*\(/i, `${writer.name} must write its order in the same transaction`);
  }
  assert.match(writers[0].body, /p_listing_type\s*=\s*'product'/i);
  assert.match(writers[0].body, /p_listing_type\s*=\s*'service'/i);
  assert.match(writers[1].body, /'product'\s*,\s*v_p\.id/i);
  assert.match(writers[2].body, /'buyer_demand'\s*,\s*v_demand\.id/i);
});

test('Product negotiation acceptance remains an independently audited order writer', () => {
  const body = readFunction(productNegotiations, 'create or replace function private.respond_to_product_price_negotiation(');
  assert.match(body, /from\s+public\.products\s+where\s+id\s*=\s*v_n\.product_id\s+for\s+update/i);
  assert.match(body, /v_p\.listing_status\s*<>\s*'approved'/i);
  assert.match(body, /insert\s+into\s+public\.commerce_orders/i);
  assert.doesNotMatch(body, /private\.create_commerce_order\s*\(/i);
});
