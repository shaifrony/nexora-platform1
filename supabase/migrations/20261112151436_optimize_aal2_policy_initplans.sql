-- Optimize AAL2 checks in Admin metadata RLS policies using initplans.
-- Keep the same access rules while evaluating the JWT once per statement.

drop policy if exists "admin departments read" on public.admin_departments;
create policy "admin departments read"
on public.admin_departments for select to authenticated
using (
  ((select auth.jwt()) ->> 'aal') = 'aal2'
  and (
    public.is_nexora_super_admin()
    or exists (
      select 1 from public.admin_staff s
      where s.user_id = (select auth.uid()) and s.is_active = true
    )
  )
);

drop policy if exists "admin permission catalog read" on public.admin_permission_catalog;
create policy "admin permission catalog read"
on public.admin_permission_catalog for select to authenticated
using (
  ((select auth.jwt()) ->> 'aal') = 'aal2'
  and (
    public.is_nexora_super_admin()
    or exists (
      select 1 from public.admin_staff s
      where s.user_id = (select auth.uid()) and s.is_active = true
    )
  )
);

drop policy if exists "admin grants self or superadmin read" on public.admin_permission_grants;
create policy "admin grants self or superadmin read"
on public.admin_permission_grants for select to authenticated
using (
  public.is_nexora_super_admin()
  or (
    ((select auth.jwt()) ->> 'aal') = 'aal2'
    and admin_user_id = (select auth.uid())
    and exists (
      select 1 from public.admin_staff s
      where s.user_id = (select auth.uid())
        and s.is_active = true
        and s.admin_level = 'assistant_admin'
    )
  )
);

drop policy if exists "admin staff self or superadmin read" on public.admin_staff;
create policy "admin staff self or superadmin read"
on public.admin_staff for select to authenticated
using (
  public.is_nexora_super_admin()
  or (
    ((select auth.jwt()) ->> 'aal') = 'aal2'
    and user_id = (select auth.uid())
    and is_active = true
  )
);
