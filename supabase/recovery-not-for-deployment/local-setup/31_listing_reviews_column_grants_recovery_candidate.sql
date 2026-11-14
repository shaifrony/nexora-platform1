-- NEXORA RECOVERY CANDIDATE — NOT AN ACTIVE MIGRATION.
-- Purpose: remove direct API access to private review columns while preserving
-- the public review list and SECURITY INVOKER aggregate RPC.
-- Apply only to a disposable local replay after Foundation/migration history
-- has been reconciled. Never apply this file to NEXORA-TEST or Live/Production.
begin;

revoke select on table public.listing_reviews from public, anon, authenticated;

grant select (
  id,
  listing_type,
  listing_id,
  rating,
  review_title,
  review_body,
  reviewer_label,
  purchased_quantity,
  review_status,
  created_at
) on table public.listing_reviews to anon, authenticated;

commit;
