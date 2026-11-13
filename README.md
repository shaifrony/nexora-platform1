# NEXORA

NEXORA is a **single-domain, role-based platform**: one homepage, one login and one shared backend.

- Planned public domain: `nexora.com`.
- Homepage public registration offers exactly Buyer, Seller and Porter; administrative roles are never exposed there.
- Porter accounts remain pending until the required Admin/Transport approval. Only approved, active Porters receive the Porter workspace.
- Buyers, Sellers, Director, Managing Director and department officers enter through the same login.
- After authentication, each active account is routed to its permitted workspace.
- Administration is a protected area inside the same application; no separate Admin URL is required.
- Shared backend: Supabase Auth, Database and Storage. Server-side RLS/RPC/Edge Function authorization is the security boundary.

See:
- [Single-domain architecture and phased delivery plan](docs/NEXORA_PROJECT_STRUCTURE.md)
- [Development work tracker](docs/NEXORA_WORK_TRACKER.md)
- [Organization governance](docs/NEXORA_ORGANIZATION_GOVERNANCE.md)

All changes are staged on `nexora-development`; the domain and role-based dashboard routing are not live until tested and deployed with approval.