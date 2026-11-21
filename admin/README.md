# Legacy Administration Prototype

NEXORA's approved architecture is now a **single-domain application** with role-based protected workspaces inside the root app.

- Do not configure a separate Vercel project for this folder.
- Do not attach `admin.nexora.com`.
- The active Administration workspace is the protected `administrationDashboard` section in the root application.
- Keep these files temporarily as reference; remove only after code review confirms no reusable code remains.
