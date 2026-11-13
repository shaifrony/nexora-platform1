# NEXORA Administration App

This directory is the independent frontend root for the future `admin.nexora.com` Vercel project.

## Local / Preview configuration

1. Create a separate Vercel project connected to the same Git repository.
2. Set its Root Directory to `admin`.
3. Keep the Marketplace Vercel project Root Directory at repository root.
4. Attach `admin.nexora.com` only after the domain is owned and the project is approved.
5. Do not deploy this app to production until the Admin authorization and backend migration release gates pass.

## Current implementation

- Supabase password sign-in.
- TOTP MFA challenge gate (aal2 required).
- Active `admin_staff` account check.
- Permission visibility from `admin_permission_grants`.
- Director/department dashboard shell.

This is a foundation only. Operational department screens, central staff provisioning UI, reports and audit views will be moved here in later workstreams. Existing Admin UI in the Marketplace root is legacy and must remain until feature parity and E2E tests are complete.

The app intentionally has no service-role key. All privileged writes must go through authenticated server-side RPCs/Edge Functions.