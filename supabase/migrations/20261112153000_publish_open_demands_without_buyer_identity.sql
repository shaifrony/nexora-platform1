-- Public Demand Board: expose only the fields required to evaluate an open wholesale demand.
-- Buyer identity and account identifiers remain private.
drop policy if exists demands_public_open_read on public.buyer_demands;
create policy demands_public_open_read
on public.buyer_demands
for select
to anon
using (demand_status = 'open');

grant select (
  id,
  demand_code,
  product_name,
  category,
  description,
  specifications_quality,
  required_quantity,
  budget,
  currency,
  destination_country,
  destination_city,
  required_date,
  demand_status,
  created_at
) on public.buyer_demands to anon;