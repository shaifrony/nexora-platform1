# NEXORA

NEXORA is being organized as two web applications in one repository.

- Marketplace app: repository root (`index.html`, `auth.js`, `marketplace.js`).
- Administration app: `admin/` (`admin/index.html`, `admin/admin.js`, `admin/admin.css`).
- Shared backend: Supabase Auth, Database and Storage with role/permission-based access control.

See:
- [Project structure and phased delivery plan](docs/NEXORA_PROJECT_STRUCTURE.md)
- [Live development tracker](docs/NEXORA_WORK_TRACKER.md)
- [Organization governance](docs/NEXORA_ORGANIZATION_GOVERNANCE.md)

All changes on `nexora-development` are staging work only. Do not assume the two apps are live at separate domains until Vercel project configuration, domain attachment, security review and E2E tests are complete.