-- NEXORA RECOVERY TEST — run after applying
-- 31_listing_reviews_column_grants_recovery_candidate.sql
-- only in a disposable local database with the full migration chain replayed.
-- This script is read-only and raises an exception if the grant boundary is wrong.
begin;

do $$
declare
  v_role text;
  v_public_column text;
  v_private_column text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if has_table_privilege(v_role, 'public.listing_reviews', 'SELECT') then
      raise exception '% still has table-level SELECT on listing_reviews', v_role;
    end if;

    foreach v_public_column in array array[
      'id','listing_type','listing_id','rating','review_title','review_body',
      'reviewer_label','purchased_quantity','review_status','created_at'
    ] loop
      if not has_column_privilege(v_role, 'public.listing_reviews', v_public_column, 'SELECT') then
        raise exception '% is missing intended public SELECT column %', v_role, v_public_column;
      end if;
    end loop;

    foreach v_private_column in array array['buyer_id','reviewed_by','moderation_note'] loop
      if has_column_privilege(v_role, 'public.listing_reviews', v_private_column, 'SELECT') then
        raise exception '% can still SELECT private review column %', v_role, v_private_column;
      end if;
    end loop;
  end loop;

  if not has_function_privilege('anon', 'public.get_listing_review_summary(text,uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_listing_review_summary(text,uuid)', 'EXECUTE') then
    raise exception 'Public review summary RPC execute grant unexpectedly missing';
  end if;
end;
$$;

-- SECURITY INVOKER smoke test: this query must run under anon with column grants
-- and RLS, returning one aggregate row (zero counts if no matching reviews).
set local role anon;
select * from public.get_listing_review_summary(
  'product',
  '00000000-0000-0000-0000-000000000000'::uuid
);
reset role;
rollback;
