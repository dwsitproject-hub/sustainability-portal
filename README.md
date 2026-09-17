# SLMS - Sustainability Certification and Licensing Management System

A comprehensive monorepo for managing sustainability certifications and business licenses. Built with modern technologies including Next.js and NestJS.

## 🏗️ Architecture

```
slms/
├── apps/
│   ├── web/        # Next.js 14 App Router - Public + Admin portal
│   └── api/        # NestJS - Backend API with Prisma
├── packages/
│   └── shared/     # Shared types, DTOs, and constants
└── infra/          # Docker Compose infrastructure
```

## 🌐 Service URLs

| Service | URL | Description |
|---------|-----|-------------|
| **Web Portal** | http://localhost:3000 | Public and admin sustainability portal |
| **API Swagger** | http://localhost:3001/docs | API documentation |
| **API Endpoint** | http://localhost:3001/api/v1 | REST API |
| **Mailhog** | http://localhost:8025 | Email testing UI |

## 📋 Prerequisites

- **Node.js** >= 20.0.0
- **pnpm** >= 8.0.0
- **Docker** & **Docker Compose**

## 🚀 Quick Start

From the **repository root** (e.g. `sustainability-portal/`).

### 1. Install Dependencies

```bash
pnpm install
```

### 2. Build Shared Package

```bash
pnpm build:shared
```

### 3. Configure Environment Files (first time only)

```bash
pnpm setup:env
```

This copies `apps/api/env.example` → `apps/api/.env` and `apps/web/env.example` → `apps/web/.env.local` if they don't exist. Or manually:

```bash
# API (local)
cp apps/api/env.example apps/api/.env

# Web (local)
cp apps/web/env.example apps/web/.env.local
```

### 4. Start Infrastructure (Docker)

```bash
pnpm dev:infra
```

This starts **only** Postgres, Redis, and Mailhog (API and Web run locally in the next step). Document files are stored under `./data/storage` when using Docker API, or set `STORAGE_ROOT_PATH` for local API. Wait ~30 seconds, then verify:

```bash
docker ps
```

### 5. Setup Database

```bash
# Run migrations
pnpm db:migrate

# Seed initial data (roles, permissions, notification rules)
pnpm db:seed
```

For other environments, use dedicated files (for example):

- `apps/api/.env.dev`, `apps/api/.env.uat`, `apps/api/.env.prod`
- `apps/web/.env.dev.local`, `apps/web/.env.uat.local`, `apps/web/.env.prod.local`

Each environment **must** have:

- Its own `DATABASE_URL` and `STORAGE_ROOT_PATH` (no sharing between local/dev/uat/prod).
- Server runtimes that use ApsaraDB RDS: set a full `DATABASE_URL` (including `sslmode`) and after cutover start only `redis` and `api`.
- Strong, unique `JWT_SECRET`, `JWT_REFRESH_SECRET`, and `JWT_ADMIN_SECRET` (do not reuse `env.example` placeholders).

### 6. Start Development

```bash
# Start API + Web concurrently (infra must already be running)
pnpm dev
```

This starts:
- **API** on http://localhost:3001
- **Web** on http://localhost:3000

**One-command setup:** `pnpm setup` does install, build:shared, setup:env, dev:infra, wait, db:migrate, and db:seed. Then run `pnpm dev`. See [docs/LOCAL_SETUP.md](docs/LOCAL_SETUP.md) for detailed local run steps (including Windows).

## 📜 Available Commands

### Development

| Command | Description |
|---------|-------------|
| `pnpm dev` | Start API + CMS + Web concurrently |
| `pnpm dev:api` | Start only NestJS API |
| `pnpm dev:cms` | Start only Strapi CMS |
| `pnpm dev:web` | Start only Next.js web portal |

### Infrastructure

| Command | Description |
|---------|-------------|
| `pnpm dev:infra` | Start infra only (postgres, redis, mailhog) for local dev |
| `pnpm dev:infra:full` | Start infra + API + Web in Docker |
| `pnpm dev:infra:logs` | View infrastructure logs |
| `pnpm dev:infra:down` | Stop infrastructure |
| `pnpm dev:infra:reset` | Stop and remove all data (volumes) |
| `pnpm setup:env` | Copy env examples to `.env` / `.env.local` if missing |

### Database

| Command | Description |
|---------|-------------|
| `pnpm db:migrate` | Run Prisma migrations (production) |
| `pnpm db:migrate:dev` | Run Prisma migrations (development) |
| `pnpm db:seed` | Seed database with initial data |
| `pnpm db:studio` | Open Prisma Studio GUI |
| `pnpm db:generate` | Regenerate Prisma client |
| `pnpm db:reset` | Reset database (drops all data!) |

### Build & Quality

| Command | Description |
|---------|-------------|
| `pnpm build` | Build all applications |
| `pnpm build:shared` | Build shared package |
| `pnpm lint` | Run ESLint on all apps |
| `pnpm format` | Format code with Prettier |
| `pnpm typecheck` | Run TypeScript checks |
| `pnpm clean` | Clean all build artifacts |

## 🔧 Configuration

### Infrastructure Services

| Service | Port | Credentials |
|---------|------|-------------|
| PostgreSQL | 5544 | user: `slms`, password: `slms`, db: `slms` |
| Redis | 6379 | (no auth) |
| Document storage | `./data/storage` | Bind mount when API runs in Docker |
| Mailhog SMTP | 1025 | (no auth) |
| Mailhog UI | 8025 | (no auth) |

### Environment Variables

**API (`apps/api/.env` – local example):**
```env
PORT=3001
DATABASE_URL="postgresql://slms:slms@localhost:5544/slms?schema=public"
JWT_SECRET=your-secret-key
STORAGE_ROOT_PATH=./data/storage
API_PUBLIC_BASE_URL=http://localhost:3001/api/v1
```

In `NODE_ENV=production` or `NODE_ENV=uat`, the API will **refuse to start** if:

- Any JWT secret (`JWT_SECRET`, `JWT_REFRESH_SECRET`, `JWT_ADMIN_SECRET`) is missing or still uses the default placeholder.
- `STORAGE_ROOT_PATH` is not set.

`infra/env.example` is intended for **local Docker-only** usage and must **not** be reused for UAT or production secrets.

**Web (`apps/web/.env.local`):**
```env
NEXT_PUBLIC_API_URL=http://localhost:3001/api/v1
```

## 🔍 Troubleshooting

### Port Conflicts

If you see "port already in use" errors:

#### Check what's using a port:

**Windows (PowerShell):**
```powershell
# Check port 3000 (Web)
netstat -ano | findstr :3000

# Check port 3001 (API)
netstat -ano | findstr :3001

# Check port 1337 (Strapi)
netstat -ano | findstr :1337

# Check port 5544 (PostgreSQL)
netstat -ano | findstr :5544
```

**Linux/macOS:**
```bash
# Check any port
lsof -i :3000
```

#### Kill a process using a port:

**Windows (PowerShell as Admin):**
```powershell
# Replace <PID> with the process ID from netstat
taskkill /PID <PID> /F
```

**Linux/macOS:**
```bash
kill -9 <PID>
```

#### Change default ports:

If you can't free a port, modify the environment files:

```env
# apps/api/.env - change API port
PORT=3002

# apps/web/.env.local - update API URL if API port changed
NEXT_PUBLIC_API_URL=http://localhost:3002/api/v1

# apps/web/package.json - change web port
"dev": "next dev -p 3010"
```

### Database Connection Issues

1. **Verify PostgreSQL is running:**
   ```bash
   docker ps | grep postgres
   ```

2. **Check PostgreSQL logs:**
   ```bash
   docker logs slms-postgres
   ```

3. **Test connection:**
   ```bash
   docker exec -it slms-postgres psql -U slms -d slms -c "SELECT 1"
   ```

4. **Reset database if corrupted:**
   ```bash
   pnpm dev:infra:reset
   pnpm dev:infra
   pnpm db:migrate
   pnpm db:seed
   ```

### Strapi / CMS

Strapi CMS is no longer used. All content and admin features are served by the single Next.js app (`apps/web`) and the NestJS API (`apps/api`).
### Redis Connection Issues

1. **Verify Redis is running:**
   ```bash
   docker ps | grep redis
   ```

2. **Test connection:**
   ```bash
   docker exec -it slms-redis redis-cli ping
   # Should return: PONG
   ```

### File upload issues

1. **Upload fails in admin:**
   - Ensure `STORAGE_ROOT_PATH` exists and is writable (local: `./data/storage`)
   - When API runs in Docker, verify the `./data/storage` bind mount in `infra/docker-compose.yml`

2. **Download/preview fails:**
   - Set `API_PUBLIC_BASE_URL` to the URL the browser uses to reach the API (e.g. `http://localhost:3001/api/v1`)

### Common Fixes

```bash
# Nuclear option: reset everything
pnpm dev:infra:reset
pnpm clean
pnpm install
pnpm build:shared
pnpm dev:infra
sleep 10  # Wait for services
pnpm db:migrate
pnpm db:seed
pnpm dev
```

## 📁 Project Structure

```
slms/
├── apps/
│   ├── api/                    # NestJS Backend
│   │   ├── prisma/
│   │   │   ├── schema.prisma   # Database schema
│   │   │   └── seed.ts         # Seed data
│   │   └── src/
│   │       ├── modules/
│   │       │   ├── auth/       # JWT authentication
│   │       │   ├── users/      # User management
│   │       │   ├── roles/      # RBAC
│   │       │   ├── notifications/
│   │       │   ├── audit-logs/
│   │       │   └── notification-engine/
│   │       └── main.ts
│   │
│   └── web/                    # Next.js Portal (public + admin)
│       └── src/
│           ├── app/            # App Router pages
│           │   ├── page.tsx          # Home
│           │   ├── policies/
│           │   ├── certifications/
│           │   ├── licenses/
│           │   ├── library/          # Document library
│           │   ├── grievance/
│           │   └── traceability/
│           ├── components/
│           └── lib/
│               └── api.ts      # API client
│
├── packages/
│   └── shared/                 # Shared code
│       └── src/
│           ├── types/
│           ├── dto/
│           └── constants/
│
└── infra/
    ├── docker-compose.yml      # Dev infrastructure
    ├── Makefile               # Shortcut commands
    └── init-db.sql            # DB initialization
```

## 🔐 Default Seeded Data

After running `pnpm db:seed`:

**Roles:**
- SustainabilityAdmin (full access)
- Legal (legal documents)
- Auditor (audit access)
- PublicReader (public content only)

**Notification Rules:**
- 90 days before expiry (EMAIL + INAPP)
- 60 days before expiry (EMAIL + INAPP)
- 30 days before expiry (EMAIL + INAPP)

## 📖 API Documentation

Visit http://localhost:3001/docs for interactive Swagger documentation.

**Public Endpoints (no auth):**
- `GET /api/v1/public/policies`
- `GET /api/v1/public/certifications`
- `GET /api/v1/public/licenses`
- `GET /api/v1/public/library`
- `GET /api/v1/public/grievances`
- `GET /api/v1/public/traceability`

**Admin Endpoints (JWT required):**
- `POST /api/v1/auth/login`
- `CRUD /api/v1/admin/documents`
- `CRUD /api/v1/admin/certifications`
- `GET /api/v1/admin/audit-logs`
- `GET /api/v1/admin/notifications`

**User Management & Admin Management:** See [docs/ADMIN-USER-MANAGEMENT.md](docs/ADMIN-USER-MANAGEMENT.md) for `/admin/users` and `/admin/admins` endpoints, RBAC, and how to seed the initial SUPER_ADMIN.

## 🤝 Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Run `pnpm lint && pnpm typecheck`
4. Submit a pull request

## 📄 License

UNLICENSED - Proprietary

---

**SLMS** - Streamlining sustainability management for a greener future 🌱
