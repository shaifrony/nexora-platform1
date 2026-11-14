create or replace function private.create_product_inquiry(
  p_product_id uuid,
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_product record;
  v_conversation_id uuid;
  v_title text;
  v_message text := left(btrim(coalesce(p_message, '')), 500);
begin
  if v_user_id is null then
    raise exception 'লগইন করে Buyer হিসেবে Inquiry পাঠান।';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_user_id and p.role = 'buyer' and p.account_status = 'active'
  ) then
    raise exception 'শুধু সক্রিয় Buyer অ্যাকাউন্ট Inquiry পাঠাতে পারবে।';
  end if;

  select p.id, p.seller_id, p.product_code, p.product_name
  into v_product
  from public.products p
  join public.business_profiles b on b.id = p.business_id
  where p.id = p_product_id
    and p.listing_status = 'approved'
    and b.approval_status = 'approved';

  if not found then
    raise exception 'পণ্যটি পাওয়া যায়নি অথবা বর্তমানে অনুমোদিত নয়।';
  end if;

  if v_product.seller_id = v_user_id then
    raise exception 'নিজের পণ্যে Inquiry পাঠানো যাবে না।';
  end if;

  v_title := left(
    'Product Inquiry • ' || v_product.product_code || ' • ' ||
    v_product.product_name ||
    case when v_message <> '' then ' • Buyer note: ' || v_message else '' end,
    900
  );

  insert into public.conversations (conversation_type, created_by, title, status)
  values ('direct', v_user_id, v_title, 'active')
  returning id into v_conversation_id;

  insert into public.conversation_participants
    (conversation_id, user_id, invited_by, invitation_status, joined_at)
  values
    (v_conversation_id, v_user_id, v_user_id, 'accepted', now()),
    (v_conversation_id, v_product.seller_id, v_user_id, 'pending', null);

  return v_conversation_id;
end;
$$;

revoke all on function private.create_product_inquiry(uuid, text) from public, anon, authenticated;
grant execute on function private.create_product_inquiry(uuid, text) to authenticated;

create or replace function public.create_product_inquiry(
  p_product_id uuid,
  p_message text default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_product_inquiry(p_product_id, p_message);
$$;

revoke all on function public.create_product_inquiry(uuid, text) from public, anon;
grant execute on function public.create_product_inquiry(uuid, text) to authenticated;
