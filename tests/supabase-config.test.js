"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "..", "supabase-config.js"), "utf8");

function configFor(hostname) {
  const window = { location: { hostname } };
  const document = { documentElement: { dataset: {} } };
  vm.runInNewContext(source, { window, document });
  return { config: window.NEXORA_SUPABASE_CONFIG, backend: document.documentElement.dataset.nexoraBackend };
}

test("known development preview routes only to NEXORA-TEST", () => {
  const { config, backend } = configFor("nexora-platform1-git-nexora-development-shaifrony-7200.vercel.app");
  assert.equal(config.environment, "test");
  assert.match(config.url, /lhxmqoyxoywntmkmmnjb\\.supabase\\.co$/);
  assert.equal(backend, "test");
});

test("known production host is explicitly labelled production", () => {
  const { config, backend } = configFor("nexora-platform1-mu.vercel.app");
  assert.equal(config.environment, "production");
  assert.match(config.url, /qsjdeqljpnjumceewsjq\\.supabase\\.co$/);
  assert.equal(backend, "production");
});

test("unknown host fails closed without any backend URL or key", () => {
  const { config, backend } = configFor("preview.example.invalid");
  assert.deepEqual(Object.keys(config).sort(), ["blocked", "environment"]);
  assert.equal(config.blocked, true);
  assert.equal(backend, "blocked");
});

test("lookalike subdomain cannot inherit an approved backend", () => {
  const { config } = configFor("nexora-platform1-git-nexora-development-shaifrony-7200.vercel.app.attacker.invalid");
  assert.equal(config.environment, "blocked");
  assert.equal(config.url, undefined);
});

test("host comparison is case-insensitive", () => {
  const { config } = configFor("NEXORA-PLATFORM1-GIT-NEXORA-DEVELOPMENT-SHAIFRONY-7200.VERCEL.APP");
  assert.equal(config.environment, "test");
});
