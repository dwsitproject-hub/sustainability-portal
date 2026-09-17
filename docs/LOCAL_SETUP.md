# Run SLMS Locally (Windows / macOS / Linux)

This guide gets the Sustainability Portal running on your machine for testing.

## Quick start (localhost:3000)

1. **Start Docker Desktop** and ensure it is running.
2. From the **repo root** in a terminal:

   ```bash
   pnpm install
   pnpm build:shared
   pnpm setup:env
   pnpm db:generate
   pnpm dev:infra
   ```
3. **Wait 20–30 seconds** for Postgres to be ready.
4. Run migrations and seed:

   ```bash
   pnpm db:migrate
   pnpm db:seed
   ```
5. Start the app:

   ```bash
   pnpm dev
   ```
6. Open **http://localhost:3000** in your browser. API: http://localhost:3001 (Swagger: http://localhost:3001/docs).

To test changes: leave `pnpm dev` running; the Next.js app and API use hot reload.

---

## Prerequisites

- **Node.js** >= 20
- **pnpm** >= 8 (`npm install -g pnpm`)
- **Docker Desktop** (PostgreSQL, Redis, Mailhog run in Docker)

## One-time setup

From the **repository root** (e.g. `d:\Project\Sustainability portal\sustainability-portal`):

### 1. Install dependencies, build shared package, and generate Prisma client

```bash
pnpm install
pnpm build:shared
pnpm db:generate
```

After a full clean (`pnpm run clean`) or fresh clone, run `pnpm db:generate` before building or running the API so the Prisma client exists.

### 2. Create environment files (if not present)

```bash
pnpm setup:env
```

This copies `apps/api/env.example` → `apps/api/.env` and `apps/web/env.example` → `apps/web/.env.local` only when those files don't exist. Edit them if you need different ports or credentials.

### 3. Start infrastructure (Docker)

```bash
pnpm dev:infra
```

This starts only **infra** services (Postgres, Redis, Mailhog). API and Web are **not** started in Docker so you can run them locally with `pnpm dev`. Document files use `STORAGE_ROOT_PATH` (local `./data/storage` or a NAS mount).

- **PostgreSQL**: `localhost:5544` (user: `slms`, password: `slms`, db: `slms`)
- **Redis**: `localhost:6379`
- **Mailhog**: `http://localhost:8025` (SMTP: `localhost:1025`)

Wait about **20–30 seconds** for Postgres to be ready.

### 4. Optional: Infra env for Docker Compose

If you run Docker from `infra/` and want to override defaults:

```bash
cd infra
copy env.example .env   # Windows
# cp env.example .env   # macOS/Linux
```

### 5. Database migrations and seed

```bash
pnpm db:migrate
pnpm db:seed
```

## Run the app (every time you develop)

With Docker infra already running:

```bash
pnpm dev
```

This starts:

- **API**: http://localhost:3001 (Swagger: http://localhost:3001/docs)
- **Web**: http://localhost:3000

## Full automated one-time setup

To do install + env + infra + wait + migrate + seed in one go:

```bash
pnpm setup
```

Then start the app with:

```bash
pnpm dev
```

## Alternative: run everything in Docker

To run API and Web in Docker as well (no local Node for app code):

```bash
pnpm dev:infra:full
```

- Web: http://localhost:3000 (mapped from container port 3000)
- API: http://localhost:3001

## Troubleshooting

### Port already in use (Windows)

```powershell
netstat -ano | findstr :3000
netstat -ano | findstr :3001
netstat -ano | findstr :5544
```

Kill process by PID (run PowerShell as Administrator if needed):

```powershell
taskkill /PID <PID> /F
```

### Docker not running / "failed to connect to the docker API"

If you see **"failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine"** or **"The system cannot find the file specified"**, the Docker daemon is not running.

1. **Start Docker Desktop** from the Start menu and wait until it has fully started (whale icon in the system tray is steady, not "Starting…").
2. If it never finishes starting: **Quit Docker Desktop** (right‑click whale icon), then start it again. On Windows with WSL2, try in an elevated PowerShell: `wsl --shutdown`, then start Docker Desktop again.
3. If Docker Desktop is not installed: install it from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/), then restart Windows if prompted.
4. When the whale icon is steady, run `docker info` or `docker ps` in a terminal. If they succeed, run `pnpm dev:infra` from the project root.

**If a container’s “log” shows the same npipe error:** that message is from Docker Desktop (or the Docker CLI) failing to reach the daemon—it is not from the container itself. Start Docker Desktop and wait until it is fully running; then container logs will load normally.

### Login returns “fetch failed”

The site loads but login fails with “fetch failed” when the **API is not running** on port 3001. Use **`pnpm dev`** from the project root to start both the API and the Web app. The API also fails to start if it cannot reach the database.

1. **Start Docker Desktop** (required for Postgres).
2. Start infra: `pnpm dev:infra` and wait ~20–30 seconds.
3. From the project root, run `pnpm dev` (starts both API on 3001 and Web on 3000). If needed, stop with Ctrl+C and run `pnpm dev` again.
4. Confirm the API is up: open http://localhost:3001/api/v1/health (or check the terminal for “Nest application successfully started” and “running on … 3001”).
5. Try logging in again at http://localhost:3000.

**Admin login shows "Cannot reach the API" (Docker stack):** If you use the app at **http://localhost:3002**, the web container proxies to the API container. Check in Docker Desktop that **slms-api** is running and open its **Logs** for errors (e.g. DB connection). From your PC, open **http://localhost:3001/api/v1/health** in a browser; if it does not load, the API is not reachable—restart the **slms-api** container or fix the cause in its logs.

### Database connection failed

1. Check Postgres: `docker ps | findstr postgres`
2. Wait a bit and run again: `pnpm db:migrate`
3. Reset infra and retry: `pnpm dev:infra:down` then `pnpm dev:infra` (wait 30s) then `pnpm db:migrate` and `pnpm db:seed`

### Reset everything (infra + DB)

```bash
pnpm dev:infra:down
pnpm dev:infra:reset
pnpm dev:infra
# wait ~30s
pnpm db:migrate
pnpm db:seed
pnpm dev
```

## Summary of npm scripts

| Command | Description |
|--------|-------------|
| `pnpm setup:env` | Copy API/Web env examples to `.env` / `.env.local` if missing |
| `pnpm dev:infra` | Start only Postgres, Redis, Mailhog (for local dev) |
| `pnpm dev:infra:full` | Start infra + API + Web in Docker |
| `pnpm dev` | Run API + Web locally (expects infra already up) |
| `pnpm setup` | install + build:shared + setup:env + dev:infra + wait + db:migrate + db:seed |
