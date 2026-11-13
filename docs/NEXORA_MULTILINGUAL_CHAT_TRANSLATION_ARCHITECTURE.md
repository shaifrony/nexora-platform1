# NEXORA — Multilingual Chat Translation Architecture

Updated: 2026-11-13  
Branch: `nexora-development`  
Status: **Architecture staged; automatic translation disabled**

## 1. Goal and invariants

A message written in one language should be readable by each accepted recipient in that recipient's own preferred language. The same shared workflow applies to Buyer, Seller, Porter and Admin, without expanding any role's access to private conversations.

Non-negotiable rules:

- The original `messages.body` is immutable from the translation workflow and remains the source of truth.
- A translation is a separate, recipient-language cache row tied to the exact message and conversation.
- A recipient sees a translation only if they are an accepted participant of that conversation.
- Missing, failed, stale or unsupported translations fall back to the original message; chat sending/receiving must never be blocked by translation.
- The UI must offer Original / Translation switching and clearly identify machine translation.
- Never translate or alter commercial facts such as prices, currency codes, quantities, measurement units, Product IDs, Order IDs, dates, tracking codes or addresses. For structured system/negotiation events, translate only display labels and human-authored notes; render numeric and identifier fields from their typed values.
- Attachments remain unchanged in the first release. Do not send image, audio, video or document contents to a translation provider.
- Admin must not gain access to private chat content merely because translation is enabled.

## 2. Proposed request flow

1. The sender posts a normal message using the existing Chat API. No translation provider is called from the browser.
2. Each accepted recipient's saved `preferred_language` is read independently.
3. If recipient language differs from detected/source language, a trusted server-side job checks the cache using `(message_id, target_language)`.
4. On cache miss, the server-side translation adapter calls the configured provider. The provider is not called if no approved provider configuration and required consent are present.
5. The server validates response size and language fields, then writes the translation using a trusted server credential. The original message is never overwritten.
6. Realtime/UI refresh picks up the translation. Chat List preview and open conversation use the recipient's language; the recipient can switch to the original.
7. If the provider is unavailable, pair unsupported, rate-limited or times out, show the original and a non-blocking translation status.

The initial release should translate text messages on demand. A durable queue/worker can be added when traffic requires retries, batching and back-pressure; do not rely on a long-running request for large backlogs.

## 3. Server-side boundary

- Browser code may send only a message ID and the recipient's selected target language to an authenticated translation endpoint. It must not send arbitrary conversation IDs as proof of access or choose another user's language.
- The endpoint must validate the JWT, load the caller's own language preference, read the message through caller-scoped RLS, and verify accepted conversation membership before provider access.
- A server-only secret may be used for the cache write after the membership check. Never expose Supabase secret/service-role credentials or provider credentials to browser/mobile code.
- Do not log message bodies, translations, provider request payloads, access tokens or secret values.
- Use idempotency on message + target language, bounded input/output length, per-user/conversation rate limits, provider timeout, and strict error handling.
- The translation cache remains read-only to authenticated clients. No direct client insert/update/delete grants.
- A translation result must be attached to the same conversation as its source message; retain the existing composite foreign-key protection.

## 4. Provider decision and zero-budget constraint

No provider has been selected or configured. Automatic translation therefore remains disabled.

Candidate for a future self-hosted evaluation: **LibreTranslate / Argos Translate**. Its software is open source and can be self-hosted, but that does not make an always-available public translation server free: compute, memory, bandwidth, uptime and maintenance still have costs. The hosted LibreTranslate service documents paid API-key access. Its language-pair coverage and quality—especially Bangla ↔ Arabic and Bangla ↔ other target languages—must be tested before selection. The project must not silently send private messages to a public demo endpoint.

Decision gate before enabling any provider:
- identify the exact provider and hosting location;
- verify license, language-pair coverage, quality and operational limits;
- disclose what private message text is sent, to whom, and for what purpose;
- obtain meaningful user consent for external processing where applicable;
- establish retention/deletion, security, cross-border transfer and incident-response rules;
- confirm an affordable operating plan. No paid dependency is assumed or authorized by this document.

## 5. Language and content handling

- Use each recipient's `user_language_preferences.preferred_language`; do not use the sender's preference as the recipient target.
- Detect source language server-side when the sender does not supply a trusted source language. A sender-provided language hint is not an authorization signal.
- Normalize language tags consistently (for example `bn`, `ar`, `en`, optionally region tags).
- First release: plain text messages only. Attachments, voice messages, call audio/video and transcripts are excluded.
- Negotiation/system messages: parse the structured event and render translated templates. Keep price, currency, quantity, unit, negotiation state, order ID and dates from typed fields. Do not translate serialized JSON as free text.
- Buyer Demand, Seller quotation, Order, Delivery and Porter notifications should use the same translation layer later, with role-scoped data projections and typed templates.

## 6. Rollout stages

1. **Foundation (staged):** language preferences, private translation cache, accepted-participant read policy and shared language selector. Complete in source; not deployed.
2. **Provider/privacy gate:** select and approve a provider, hosting model, consent language and cost/retention policy. Not complete.
3. **Trusted translation endpoint:** JWT + participant validation, provider adapter, secret handling, cache write, idempotency, rate limits and timeout. Not implemented.
4. **Recipient UI:** translated Chat List previews, message translation display, Original/Translation toggle, loading/error/fallback states. Not implemented.
5. **Structured events:** negotiation, Demand, order and delivery templates. Not implemented.
6. **Verification:** unit tests, provider pair tests, local SQL/RLS tests, real authenticated JWT/PostgREST, Realtime and browser/mobile E2E across Buyer/Seller/Porter/Admin. Not run.

## 7. Current safety and deployment status

- The existing staged migration `20261115120000_multilingual_chat_foundation.sql` is not applied.
- Migration history divergence remains a deployment blocker. Do not apply or deploy this work until history is reconciled and an isolated rehearsal passes.
- No provider URL, API key, secret, consent toggle or translation Edge Function has been configured.
- No SQL, hosted test, browser E2E or translation quality test was run for this architecture update.
- No Live Supabase, Production, DNS or `main` branch was changed.
