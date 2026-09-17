# Step-by-step: Deploy new changes (with migrations) to dev

Use this when you have **pulled the latest `dev`** branch and need to deploy to your dev environment (two-server: backend 172.28.92.57, frontend 172.28.92.56, or your actual dev hosts).

**If the server has been crashing or is low on space** (lots of Docker/build cache), run cache cleanup **before** deploying — see [§ 5. Cache cleanup](#5-cache-cleanup-recommended-on-constrained-dev-servers) below.

**New migrations in this release (applied automatically when API starts):**

- `20260223000000_add_password_reset_tokens` – table for forgot-password reset tokens  
- `20260223025654_migration_forgot_password` – forgot-password support  
- `20260224024137_add_admin_user_management_and_audit_fields` – admin user management and audit fields  

The API **entrypoint runs `prisma migrate deploy`** on every container start, so migrations run automatically after you rebuild and restart the API.

---

## 1. Backend server (API + Postgres + Redis + MinIO)

### 1.1 Pull latest code

```bash
cd /path/to/sustainability-portal
git fetch origin
git checkout dev
git pull origin dev
```

### 1.2 Rebuild and start the backend stack

Rebuilding the API image ensures the new migration files and code are inside the container.

**Option A – using the dev script (recommended):**

```bash
./infra/up-dev-backend.sh up -d --build api
```

Use `build --no-cache api` only when troubleshooting stale cache or dependency issues.

**Option B – raw compose (ensure `infra/.env` or `infra/.env.be.dev` exists):**

```bash
docker compose --env-file infra/.env -f infra/docker-compose.dev.backend.yml up -d --build api
```

- **First time or no existing DB:** Postgres/Redis/MinIO start; then the API starts and runs `prisma migrate deploy` (all migrations, including the new ones), then the app listens.
- **Existing DB:** Same; Prisma will only apply migrations that are not yet in `_prisma_migrations`.

### 1.3 Check that migrations ran

**Option A – API logs (quick):**

```bash
docker compose -f infra/docker-compose.dev.backend.yml logs api
```

Look for lines like:

- `Applying migration \`20260223000000_add_password_reset_tokens\``  
- `Applying migration \`20260223025654_migration_forgot_password\``  
- `Applying migration \`20260224024137_add_admin_user_management_and_audit_fields\``  

(Only pending ones appear.) Then the app should listen (e.g. “Nest application successfully started” or “listening on port 3001”).

**Option B – Migrate status:**

```bash
docker compose -f infra/docker-compose.dev.backend.yml exec api npx prisma migrate status
```

Expected: **“Database schema is up to date!”** and no pending migrations.

### 1.4 (Optional) Run seed

If you need to reset or refresh seed data (e.g. admin user, policies):

```bash
docker compose -f infra/docker-compose.dev.backend.yml exec api npx prisma db seed
```

Run once after migrations. If seed is already up to date, this is safe to run again.

### 1.5 Health check

```bash
curl -s http://localhost:3001/api/v1/health
# Or from your PC (use backend public IP if different):
# curl -s http://<backend-public-ip>:3001/api/v1/health
```

You should get a 200 JSON response.

---

## 2. Frontend server (Next.js web)

### 2.1 Pull latest code

```bash
cd /path/to/sustainability-portal
git fetch origin
git checkout dev
git pull origin dev
```

### 2.2 Rebuild and start the frontend

**Option A – using the dev script (recommended):**

```bash
./infra/up-dev-frontend.sh up -d --build web
```

**Option B – raw compose (requires `infra/.env.fe.dev`):**

```bash
docker compose --env-file infra/.env.fe.dev -f infra/docker-compose.dev.frontend.yml up -d --build web
```

`--build` rebuilds only changed Docker layers (lockfile, api/shared source). On memory‑constrained servers, run `./infra/clean-dev-cache.sh` first if disk is low.

### 2.3 Check the web container

```bash
./infra/up-dev-frontend.sh ps
./infra/up-dev-frontend.sh logs web --tail 30
```

Web should be listening on port 3000.

---

## 3. Quick checklist

| Step | Where | Command / check |
|------|--------|------------------|
| 0 | Either (if low on space) | `./infra/clean-dev-cache.sh` to free Docker cache |
| 1 | Backend | `git pull origin dev` |
| 2 | Backend | `./infra/up-dev-backend.sh up -d --build api` |
| 3 | Backend | `./infra/up-dev-backend.sh logs api` → confirm migrations + app started |
| 4 | Backend | (optional) `./infra/up-dev-backend.sh exec api npx prisma db seed` |
| 5 | Backend | `curl -s http://localhost:3001/api/v1/health` → 200 OK |
| 6 | Frontend | `git pull origin dev` |
| 7 | Frontend | `./infra/up-dev-frontend.sh up -d --build web` |
| 8 | Browser | Open `http://<frontend-public-ip>:3000` and test login, forgot-password, license page |

---

## 3.1 Routine deploy vs troubleshooting

**Routine deploy (after `git pull`):**

```bash
./infra/up-dev-backend.sh up -d --build api
./infra/up-dev-frontend.sh up -d --build web
```

**Only when troubleshooting** (stale cache, dependency weirdness):

```bash
./infra/up-dev-backend.sh build --no-cache api
./infra/up-dev-backend.sh up -d api

./infra/up-dev-frontend.sh build --no-cache web
./infra/up-dev-frontend.sh up -d web
```

---

## 4. If something goes wrong

**Migrations fail (API exits or “migrate deploy” error):**

- Check logs: `./infra/up-dev-backend.sh logs api`
- Check status: `./infra/up-dev-backend.sh exec api npx prisma migrate status`
- Ensure `infra/.env` (or `.env.be.dev`) has correct `DB_USER`, `DB_PASSWORD`, `DB_NAME` and Postgres is healthy:  
  `./infra/up-dev-backend.sh ps`

**API healthy but app features broken:**

- Confirm `CORS_ORIGIN` on backend matches the URL you use to open the app (e.g. `http://<frontend-public-ip>:3000`).
- Confirm frontend `API_URL` in `infra/.env` is the URL the **browser** uses to call the API (e.g. `http://<backend-public-ip>:3001/api/v1`).

**Frontend shows old UI:**

- Rebuild: `./infra/up-dev-frontend.sh up -d --build web`
- Clear browser cache or use an incognito window.

---

## 5. Cache cleanup (recommended on constrained dev servers)

If the dev server has **little free space or has crashed** due to accumulated Docker/build cache, run this periodically or before a heavy deploy:

```bash
# From repo root (on backend or frontend server)
./infra/clean-dev-cache.sh
```

This removes Docker **build cache** and **dangling images** and prints disk usage before/after. It does **not** remove your running containers or named volumes (`postgres_data`, `redis_data`).

For a more aggressive cleanup (removes all unused images; next deploy will re-pull/rebuild):

```bash
./infra/clean-dev-cache.sh --aggressive
```

**Also applied in dev:** Redis is limited to **200MB** with `allkeys-lru` eviction (`docker-compose.dev.backend.yml`) so the Redis cache cannot grow unbounded and contribute to server crash.

---

For more detail (env vars, security groups, troubleshooting), see the local `docs/DEPLOY-DEV.md` runbook (not tracked in git).
