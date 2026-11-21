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

## 8. Verified provider research (2026-11-13)

### LibreTranslate / Argos Translate
- The published Argos package index lists Bengali (bn) → English (en), Arabic (ar) → English (en), English → Bengali and English → Arabic packages. The published list does not establish a direct Bengali ↔ Arabic package.
- LibreTranslate documentation says it can pivot through an intermediate language (usually English) when a direct pair is unavailable. Therefore Bangla ↔ Arabic may require two translation hops; this is a candidate path, not a quality guarantee.
- Argos is the only candidate retained for a self-hosted proof of concept at this stage. A self-hosted server still needs compute, memory, bandwidth, monitoring and maintenance; no free always-on capacity is assumed.

### NLLB-200: not approved for NEXORA production
- Meta's facebook/nllb-200-distilled-600M model card lists CC-BY-NC 4.0 and explicitly describes the model as research-oriented, not released for production deployment; it also warns against domain-specific/legal/medical reliance and long inputs.
- NEXORA is a commercial marketplace, so the non-commercial license is a blocker unless a separate compatible commercial license is obtained. Do not download, deploy or integrate this checkpoint for production on the assumption that open weights mean commercial permission.
- NLLB may be used only in a clearly non-production research comparison if license terms and attribution are reviewed; it is not the selected engine.

### Pilot quality gate before provider approval
Create a human-reviewed, consented test set with at least 100 short messages in each direction for Bangla ↔ Arabic and Bangla ↔ English, including colloquial Bangla, spelling variation, trade terms, polite requests, negation, dates, units and mixed Bangla/English. Include separate structured-event tests. Two bilingual reviewers should score meaning preservation, omitted/added meaning, tone and protected-token preservation. Reject any provider that changes numeric values, currency, quantities, dates, product/order IDs or negation. Compare direct and English-pivot routes; do not describe a pair as supported until the exact installed model packages are verified.

### Current implementation decision
- **No translation engine is selected or enabled.** The best zero-provider-cost candidate for a later isolated test is self-hosted LibreTranslate/Argos, conditional on available hosting and a successful Bangla/Arabic pilot.
- Do not use public demo endpoints or send private conversation content to them. Do not put provider credentials in browser code.
- The next implementation milestone is a provider-neutral, disabled-by-default server adapter plus an isolated provider test harness only after a hosting target and consent policy are approved. No Edge Function was added in this research-only change.

## 9. Bengali ↔ English evaluation (2026-11-13)

### Confirmed model availability
- Argos package index currently lists Bengali → English (`bn→en`, package 1.9 / Argos 1.9.0, about 67 MB) and English → Bengali (`en→bn`, package 1.9 / Argos 1.9.0, about 68 MB). LibreTranslate confirms both directions and documents pivoting through English when a direct pair is absent.
- This confirms installable package availability only. No trustworthy, model-specific public BLEU/chrF++/COMET benchmark for these exact Argos package versions was found in the reviewed sources. Do not infer translation quality from package presence or file size.

### Stronger candidate for a Bengali-English pilot: AI4Bharat IndicTrans2
- IndicTrans2 explicitly supports Bengali (`ben_Beng`) and English (`eng_Latn`) in both directions and publishes evaluation tooling for FLORES, IN22-Gen and IN22-Conv using chrF++, BLEU and COMET.
- The official AI4Bharat model repository documents separate inference/evaluation paths for English→Indic and Indic→English. The Hugging Face model card for `ai4bharat/indictrans2-en-indic-dist-200M` identifies the checkpoint as MIT-licensed; the paired Indic→English checkpoint must also be license-checked at the exact selected revision before deployment.
- IndicTrans2 is therefore the preferred first benchmark candidate for NEXORA's Bengali ↔ English pilot, ahead of Argos. This is a candidate selection for testing, not a production approval or a claim that it has already been run by NEXORA.

### Practical constraints
- A 200M-parameter model is not a free hosted API. Self-hosting requires suitable CPU/RAM or GPU capacity, model downloads, runtime, monitoring and maintenance. Measure actual memory, latency and throughput on the intended server before deciding.
- IndicTrans2 is an Indic-language specialist; it does not replace a general multilingual engine for Arabic, Chinese, French or other non-Indic targets. Keep the provider interface language-pair-aware so the system can use different approved models for different language pairs.

### Bengali-English pilot decision
- Benchmark IndicTrans2 En↔Bn and Argos En↔Bn on the same consented, human-reviewed sample (at least 100 examples per direction). Include formal Bengali, colloquial Bengali, Banglish, short chat, business terms, negation, questions, dates, units, currency and names/IDs.
- Score meaning preservation, fluency, omissions/additions and protected-token accuracy with two bilingual reviewers; also compute chrF++/COMET where reference translations are available. BLEU alone is not an approval criterion.
- No automatic translation is enabled until the pilot, commercial-license review for both checkpoints, hosting-cost review, privacy/consent gate and server-side security review pass.


## 10. Reproducible Bengali ↔ English pilot corpus (2026-11-13)
- Added `docs/NEXORA_BN_EN_PILOT_CORPUS.md`: 24 synthetic parallel examples, usable in both directions (24 cases per direction), covering trade chat, negation, offers, quantity, price/currency, delivery, dates, units and protected IDs.
- The references are seed references, not ground truth. Two independent bilingual reviewers must validate them before scoring; disputed examples are excluded until resolved.
- The corpus includes protected-token checks, raw-output retention, per-direction human scoring, optional chrF++/COMET, and a results table that explicitly remains blank until actual inference.
- No private NEXORA chat content is used. No model was downloaded or run; no model winner/quality score is claimed. Production translation remains disabled.


## 11. Exact checkpoint and local runner gate (2026-11-13)
- Identified official distilled checkpoints: `ai4bharat/indictrans2-en-indic-dist-200M` (English→Bengali) and `ai4bharat/indictrans2-indic-en-dist-200M` (Bengali→English). Both upstream model cards display MIT license; both repositories are Hugging Face gated and require the operator to accept access conditions. The exact immutable model commit SHA must be recorded before inference.
- Despite the `200M` checkpoint naming, the current Hugging Face file listing shows a model.safetensors artifact around 1.1 GB. Do not assume a 200 MB download or run on the user's Android phone.
- Argos package index lists direct `bn→en` and `en→bn` packages at package 1.9 / Argos 1.9.0. The index metadata does not state the package artifact license; production/commercial rights remain unverified pending inspection of the exact downloaded artifacts and terms.
- Added `scripts/translation_pilot/run_bn_en_pilot.py` and `docs/NEXORA_BN_EN_MODEL_RUNBOOK.md`. Runner reads the synthetic 24-pair corpus, pins IndicTrans2 to 40-character revisions, uses only local inference, and writes raw outputs + latency to CSV. It does not auto-score or declare a winner.
- No model was downloaded or run in this environment; no quality score or model winner is claimed. The runner is source-prepared but not runtime-tested. Automatic translation remains disabled.
