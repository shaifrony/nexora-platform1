-- NEXORA RECOVERY TEST — run after applying
-- 31_listing_reviews_column_grants_recovery_candidate.sql
-- only in a disposable local database with the full migration chain replayed.
-- This script is read-only and raises an exception if the grant boundary is wrong.
begin;

do $$
declare
  v_role text;
  v_privilege text;
  v_column record;
  v_expected_public boolean;
  v_expected_columns text[] := array[
    'id','listing_type','listing_id','rating','review_title','review_body',
    'reviewer_label','purchased_quantity','review_status','created_at'
  ];
  v_table_privileges text[] := array[
    'SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'
  ];
begin
  foreach v_role in array array['anon','authenticated'] loop
    -- API roles must have no table-level privilege of any kind.
    foreach v_privilege in array v_table_privileges loop
      if has_table_privilege(v_role, 'public.listing_reviews', v_privilege) then
        raise exception '% still has table-level % on listing_reviews', v_role, v_privilege;
      end if;
    end loop;

    -- Inspect every live column, so a future schema addition cannot silently
    -- become public merely because this test forgot to name the new column.
    for v_column in
      select a.attname
      from pg_catalog.pg_attribute a
      where a.attrelid = 'public.listing_reviews'::regclass
        and a.attnum > 0
        and not a.attisdropped
    loop
      v_expected_public := v_column.attname = any(v_expected_columns);
      if has_column_privilege(v_role, 'public.listing_reviews', v_column.attname, 'SELECT')
         is distinct from v_expected_public then
        raise exception '% SELECT privilege mismatch for listing_reviews.% (expected public: %)',
          v_role, v_column.attname, v_expected_public;
      end if;
    end loop;
  end loop;

  if not has_function_privilege('anon', 'public.get_listing_review_summary(text,uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_listing_review_summary(text,uuid)', 'EXECUTE') then
    raise exception 'Public review summary RPC execute grant unexpectedly missing';
  end if;
end;
$$;

-- Direct public-column query must parse and execute under both API roles.
-- WHERE false avoids exposing even public review content in this test output.
set local role anon;
select id, listing_type, listing_id, rating, review_title, review_body,
       reviewer_label, purchased_quantity, review_status, created_at
from public.listing_reviews where false;
select * from public.get_listing_review_summary(
  'product',
  '00000000-0000-0000-0000-000000000000'::uuid
);
reset role;

set local role authenticated;
select id, listing_type, listing_id, rating, review_title, review_body,
       reviewer_label, purchased_quantity, review_status, created_at
from public.listing_reviews where false;
select * from public.get_listing_review_summary(
  'product',
  '00000000-0000-0000-0000-000000000000'::uuid
);
reset role;
rollback;
