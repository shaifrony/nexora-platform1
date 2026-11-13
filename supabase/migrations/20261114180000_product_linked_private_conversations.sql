-- NEXORA: Product-linked private conversations for Buyer and Seller.
-- Staged source only. Do not apply until migration history is reconciled and reviewed.
begin;

alter table public.conversations
  add column if not exists context_type text not null default 'general',
  add column if not exists context_product_id uuid references public.products(id) on delete set null,
  add column if not exists context_seller_id uuid references public.profiles(id) on delete set null,
  add column if not exists context_product_slug text,
  add column if not exists context_product_name text,
  add column if not exists context_product_image_url text,
  add column if not exists context_product_price numeric(18,2),
  add column if not exists context_product_currency text;

alter table public.conversations
  drop constraint if exists conversations_context_type_check,
  add constraint conversations_context_type_check
    check (context_type in ('general','product','demand')),
  drop constraint if exists conversations_product_context_check,
  add constraint conversations_product_context_check
    check (
      (context_type <> 'product')
      or (
        conversation_type = 'direct'
        and context_seller_id is not null
        and context_product_slug is not null
        and context_product_name is not null
        and context_product_price is not null
        and context_product_price >= 0
        and context_product_currency ~ '^[A-Z]{3}$'
      )
    );

create unique index if not exists conversations_one_product_thread_per_buyer_seller
  on public.conversations(created_by, context_seller_id, context_product_id)
  where context_type = 'product' and context_product_id is not null
    and conversation_type = 'direct' and status = 'active';

create index if not exists conversations_context_seller_updated_idx
  on public.conversations(context_seller_id, updated_at desc)
  where context_type = 'product';

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
    raise exception 'লগইন করে Buyer হিসেবে Inquiry পাঠান।' using errcode='42501';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_user_id and p.role = 'buyer' and p.account_status = 'active'
  ) then
    raise exception 'শুধু সক্রিয় Buyer অ্যাকাউন্ট Inquiry পাঠাতে পারবে।' using errcode='42501';
  end if;

  select p.id, p.seller_id, p.product_code, p.product_name, p.slug,
         p.image_urls, p.price, p.currency
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
    raise exception 'নিজের পণ্যে Inquiry পাঠানো যাবে না.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_product.seller_id and p.role = 'seller' and p.account_status = 'active'
  ) then
    raise exception 'বিক্রেতার অ্যাকাউন্ট বর্তমানে সক্রিয় নয়।';
  end if;

  v_title := left('Product • ' || v_product.product_code || ' • ' || v_product.product_name, 900);

  insert into public.conversations (
    conversation_type, created_by, title, status,
    context_type, context_product_id, context_seller_id,
    context_product_slug, context_product_name, context_product_image_url,
    context_product_price, context_product_currency
  ) values (
    'direct', v_user_id, v_title, 'active',
    'product', v_product.id, v_product.seller_id,
    v_product.slug, v_product.product_name, v_product.image_urls[1],
    v_product.price, v_product.currency
  )
  on conflict (created_by, context_seller_id, context_product_id)
    where context_type = 'product' and context_product_id is not null
      and conversation_type = 'direct' and status = 'active'
  do nothing
  returning id into v_conversation_id;

  if v_conversation_id is null then
    select c.id into v_conversation_id
    from public.conversations c
    where c.created_by = v_user_id
      and c.context_seller_id = v_product.seller_id
      and c.context_product_id = v_product.id
      and c.context_type = 'product'
      and c.conversation_type = 'direct'
      and c.status = 'active'
    limit 1;
  else
    insert into public.conversation_participants
      (conversation_id, user_id, invited_by, invitation_status, joined_at)
    values
      (v_conversation_id, v_user_id, v_user_id, 'accepted', now()),
      (v_conversation_id, v_product.seller_id, v_user_id, 'pending', null);
  end if;

  if v_conversation_id is null then
    raise exception 'Product Conversation তৈরি করা যায়নি।';
  end if;

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

commit;
