-- Centralize Admin AAL2 checks in a private helper to keep RLS policies concise.
create or replace function private.is_nexora_active_admin_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.jwt()->>'aal') = 'aal2'
    and exists (
      select 1
      from public.admin_staff s
      join public.profiles p on p.id = s.user_id
      where s.user_id = (select auth.uid())
        and s.is_active = true
        and p.role = 'admin'
        and p.account_status = 'active'
    );
$function$;

revoke all on function private.is_nexora_active_admin_staff() from public, anon;
grant execute on function private.is_nexora_active_admin_staff() to authenticated;

drop policy if exists "admin departments read" on public.admin_departments;
create policy "admin departments read"
on public.admin_departments for select to authenticated
using (
  public.is_nexora_super_admin()
  or (select private.is_nexora_active_admin_staff())
);

drop policy if exists "admin permission catalog read" on public.admin_permission_catalog;
create policy "admin permission catalog read"
on public.admin_permission_catalog for select to authenticated
using (
  public.is_nexora_super_admin()
  or (select private.is_nexora_active_admin_staff())
);

drop policy if exists "admin grants self or superadmin read" on public.admin_permission_grants;
create policy "admin grants self or superadmin read"
on public.admin_permission_grants for select to authenticated
using (
  public.is_nexora_super_admin()
  or (
    admin_user_id = (select auth.uid())
    and (select private.is_nexora_active_admin_staff())
    and exists (
      select 1 from public.admin_staff s
      where s.user_id = (select auth.uid())
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
    user_id = (select auth.uid())
    and (select private.is_nexora_active_admin_staff())
  )
);
