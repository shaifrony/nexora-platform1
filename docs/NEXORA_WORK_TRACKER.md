# NEXORA Work Tracker

Updated: 2026-11-13

Status definitions:
- **Done (staged):** code/docs are committed to development but not necessarily deployed.
- **Partial:** some foundation exists; important behavior/testing remains.
- **Pending:** not implemented.
- **Blocked:** cannot safely proceed without prerequisite, environment or explicit approval.

| Workstream | Current status | Evidence / notes |
|---|---|---|
| Two-app architecture | Done (staged) | Marketplace root + new `admin/` app shell |
| Admin authentication shell | Partial | Password login, TOTP MFA challenge, active admin lookup and permission display; not browser-tested |
| Director officer management | Partial | Form/Edge Function/SQL migration staged; DB migration and secure invite flow not tested |
| Marketplace Wholesale/Retail | Done (staged) | Category entitlements and Product market category migration/UI |
| Services marketplace | Partial | Listing flow staged; review/security tests remain |
| Buyer Demands & quotations | Partial | Matching inbox and structured quotation staged; acceptance/conversion/notifications pending |
| Commerce orders | Partial | Order lifecycle and verified review eligibility staged; payments/disputes absent |
| Reviews | Partial | Verified-purchase-only workflow staged; E2E pending |
| Delivery Network | Partial | Partner/team, assignment and tracking staged; receipt, finance and API integration pending |
| Accounts & Finance | Pending | No complete ledger, payout/refund maker-checker system |
| Reports & audit | Partial | Existing admin audit + some logs; unified departmental reporting pending |
| Separate Vercel projects/domains | Pending | Needs project configuration, domain ownership and explicit approval |
| Production release | Blocked | Migration chain mismatch, isolated DB/E2E missing, no release approval |

## Known technical blockers
1. Hosted Supabase migration history is behind Development Branch migrations. Never apply only the latest migration.
2. No isolated Supabase development database is available for migration testing.
3. Prior Vercel deployment hit a rolling 24-hour deployment cap; no retry/deploy without user approval.
4. Existing root `index.html` and `auth.js` still include legacy Admin UI. It must be migrated to the new Admin app in phases, not abruptly deleted.
5. Newly staged officer management backend needs isolated integration tests, including invite failure cleanup, duplicate staff, permission escalation, department scope, MFA bypass, and deactivation.
