# Pre-UAT Evaluation — Sustainability Portal (SLMS)

**Evaluation date:** 2026-02-23  
**Scope:** Full stack (API, Web, Auth, Security, Config, Docker). Builds on [PRE-UAT-PRE-PRODUCTION-REVIEW.md](./PRE-UAT-PRE-PRODUCTION-REVIEW.md).

---

## 1. Executive summary

Since the earlier pre-UAT review, several **P0/P1** items have been addressed. The application is in a better state for UAT, with critical security fixes (path traversal, secret validation, password reset) and improved robustness (license page, login error handling, optional Redis). Some items remain: **pagination cap** is only applied in part of the API, **file upload** has no size/type limits, **logout cookie** clearing does not fully match set-cookie options, and **PII in logs** and **Docker/operability** hardening are still open.

**UAT readiness score: 78/100**

Recommendation: **Proceed to UAT** after completing the “Must-fix before UAT” list below (estimated 1–2 hours). The remaining “Before production” and “Nice-to-have” items can be done in parallel or after UAT.

---

## 2. What’s been fixed (since previous review)

| Area | Status | Evidence |
|------|--------|----------|
| **Path traversal on file preview** | Fixed | `apps/api/src/modules/public/public.controller.ts`: `if (key.includes('..')) return 400` before pattern check. |
| **Production secret validation** | Fixed | `apps/api/src/config/configuration.ts`: `weakRefreshSecrets` and `weakAdminSecrets` include both code defaults and compose-style defaults (`refresh-secret-change-in-production`, `admin-secret-change-in-production`). App throws in production/UAT if weak secrets are used. |
| **Forgot-password / reset-password** | Implemented | `AuthController`: `POST /auth/forgot-password`, `POST /auth/reset-password`. `AuthService`: single-use token, expiry, secure reset flow. Frontend: `/forgot-password`, `/auth/reset-password`. |
| **License page 404** | Fixed | `apps/web/src/app/compliance/[sectionSlug]/page.tsx`: `/compliance/license` and `/compliance/licenses` always render license view; safe fetches and slug aliases prevent 404. |
| **Login “failed to fetch”** | Improved | `auth-api.ts`: network errors show clear message; API can start without Redis (`REDIS_ENABLED=false`) so login is reachable when only DB is up. |
| **Pagination cap (partial)** | Partially fixed | `apps/api/src/common/response.ts`: `MAX_PAGE_SIZE = 100`, `clampPagination()`. Used in **documents** and **admin-users**; **certifications**, **licenses**, **grievances**, **traceability**, **notification-engine** still use uncapped `pageSize`. |

---

## 3. Remaining gaps (prioritised)

### Must-fix before UAT

| Pri | Item | Risk | Location / Fix |
|-----|------|------|----------------|
| **P1** | **Pagination cap not applied everywhere** | Large `pageSize` can cause high load or DoS on list endpoints. | **CertificationsService**, **LicensesService**, **GrievancesService**, **TraceabilityService**, **NotificationEngineService**: use `clampPagination(params.page, params.pageSize)` (and import from `common/response`) for all list methods that accept `page`/`pageSize`. |
| **P1** | **File upload: no size or type limits** | Large uploads can exhaust memory; malicious file types can be stored. | **UploadController** (`apps/api/src/modules/upload/upload.controller.ts`): add Multer `limits: { fileSize: 25 * 1024 * 1024 }` (e.g. 25MB) and `fileFilter` to allow only safe MIME types (e.g. PDF, images, Office). Reject unknown types. |

### Must-fix before production

| Pri | Item | Risk | Location / Fix |
|-----|------|------|----------------|
| **P1** | **Logout cookie options** | If clear options don’t match set options, cookie may not be cleared (e.g. in HTTPS prod). | **AuthController** `clearUserCookie`: use same options as `setUserCookie` (e.g. `secure` when production, `sameSite: 'lax'`) so the cookie is cleared in all environments. |
| **P1** | **PII in logs** | Email addresses in logs create compliance/privacy risk. | **EmailService** (`email.service.ts`): avoid logging `options.to`; log only messageId and high-level outcome (e.g. “Email sent to 1 recipient”). |
| **P2** | **Swagger in production** | API surface exposed if left enabled. | **main.ts**: default `SWAGGER_ENABLED` to `'false'` when `NODE_ENV === 'production'`, or document that production `.env` must set `SWAGGER_ENABLED=false`. |
| **P2** | **API Dockerfile** | Run as root; no health check for orchestrators. | **apps/api/Dockerfile**: add non-root user and `USER` in runner stage; add `HEALTHCHECK` using `wget`/`curl` to `GET /api/v1/health/ready`. |
| **P2** | **Refresh token expiresAt** | Hardcoded 7 days; if `JWT_REFRESH_EXPIRES_IN` changes, stored expiry can be wrong. | **AuthService**: compute `expiresAt` from `JWT_REFRESH_EXPIRES_IN` (e.g. same parsing as for JWT expiry) instead of fixed 7 days. |

### Nice-to-have

- Stricter rate limits on auth routes (login, register, forgot-password).
- Helmet for security headers if API serves or redirects to web.
- Structured logging (correlation ID, log levels); restrict stack traces to non-prod or redact.
- Optional virus scanning for uploaded files.

---

## 4. Checklist

### Before UAT (do these first)

- [ ] **Pagination:** Use `clampPagination()` in CertificationsService, LicensesService, GrievancesService, TraceabilityService, and NotificationEngineService for all list endpoints that take `page`/`pageSize`.
- [ ] **Upload limits:** Add Multer `limits.fileSize` (e.g. 25MB) and `fileFilter` (allowlist of MIME types) to the proxy upload in UploadController.
- [ ] **Secrets:** Confirm no real secrets in repo; UAT env uses strong JWT/MinIO/DB secrets from env (not placeholders).
- [ ] **Smoke test:** Run `pnpm run build` and `pnpm run build:docker`; run full stack (`pnpm run docker:up` or `pnpm dev` + `pnpm dev:infra`); verify login, license page, forgot-password, and one admin flow.

### Before production (after UAT)

- [ ] Align logout cookie clearing with set-cookie options (secure, sameSite).
- [ ] Redact or avoid logging email addresses in EmailService (and any other PII in logs).
- [ ] Disable Swagger in production (env or NODE_ENV-based default).
- [ ] Add HEALTHCHECK and non-root user to API Dockerfile.
- [ ] Compute refresh token `expiresAt` from `JWT_REFRESH_EXPIRES_IN`.

### Optional

- Stricter rate limits on auth endpoints.
- Helmet, structured logging, virus scanning (as above).

---

## 5. Architecture snapshot (for UAT testers)

| Component | Tech | Port (dev) | Notes |
|-----------|------|------------|--------|
| Web | Next.js 14 | 3000 | Cookie-based auth; calls API via `NEXT_PUBLIC_API_URL`. |
| API | NestJS + Prisma | 3001 | Global prefix `api/v1`; JWT + refresh; admin JWT separate. |
| Postgres | PostgreSQL 16 | 5544 (host) | From `infra/docker-compose.yml` when using Docker. |
| Redis | Redis 7 | 6379 | Optional: set `REDIS_ENABLED=false` in API `.env` to run without Redis. |
| Files | Filesystem / Synology | bind mount | `STORAGE_HOST_PATH` → `/app/storage`. |
| Mailhog | SMTP capture | 1025 (SMTP), 8025 (UI) | For verification and reset emails in dev. |

**Key user flows:** Register → verify email → login → home; Forgot password → email link → reset password; Compliance → Licenses (`/compliance/license`). Admin: `/admin/login` → admin flows (categories, documents, licenses, etc.).

**Env:** API: `apps/api/.env` (required: `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET`, `JWT_ADMIN_SECRET`; optional: `REDIS_ENABLED=false`). Web: `apps/web/.env.local` (`NEXT_PUBLIC_API_URL`). Infra: `infra/.env` for Docker (Postgres, Redis, `STORAGE_HOST_PATH`).

---

## 6. Summary

- **Path traversal**, **secret validation**, **password reset**, and **license page** are in a good state for UAT.
- **Pagination** and **file upload** limits should be completed before UAT; the rest can follow before production.
- After applying the “Before UAT” checklist and a quick smoke test, the project is suitable to **proceed to UAT**.

*End of evaluation.*
