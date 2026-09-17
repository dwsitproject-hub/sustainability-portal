# Production deployment – verification and step-by-step (PuTTY)

This document has two parts:

1. **Verification** – checklist that prod preparation is complete.
2. **Step-by-step deploy** – how to deploy to two prod servers using PuTTY (SSH from Windows).

**For a much more detailed walkthrough** (every PuTTY click, nano usage, generating secrets, firewall commands, “you should see” checks, and troubleshooting), see **[PROD_DEPLOY_PUTTY_DETAILED.md](./PROD_DEPLOY_PUTTY_DETAILED.md)**.

---

## Part 1: Verification – preparation for production

Use this checklist before deploying.

### 1.1 Repo and compose files

| Item | Status | Notes |
|------|--------|--------|
| `infra/docker-compose.prod.backend.yml` | ✅ | Backend: Postgres (host 5000), Redis, API on port **8001**; files on Synology mount |
| `infra/docker-compose.prod.frontend.yml` | ✅ | Frontend: Next.js on port **8000** |
| `infra/env.example.backend` | ✅ | Copy to `.env` on **backend** server |
| `infra/env.example.frontend` | ✅ | Copy to `.env` on **frontend** server |

### 1.2 Backend env (env.example.backend)

| Variable | Required | Notes |
|----------|----------|--------|
| `DB_USER`, `DB_PASSWORD`, `DB_NAME` | Yes | Local Docker Postgres (default) |
| `DATABASE_URL` | If using ApsaraDB | Full URL including `sslmode`. See [MIGRATE-TO-APSARA-DB.md](./MIGRATE-TO-APSARA-DB.md) |
| `REDIS_PASSWORD` | Yes | Redis auth |
| `JWT_SECRET`, `JWT_REFRESH_SECRET`, `JWT_ADMIN_SECRET` | Yes | Use strong values (e.g. `openssl rand -base64 64`) |
| `CORS_ORIGIN` | Yes | Frontend origin, e.g. `http://FRONTEND_IP:8000` |
| `STORAGE_HOST_PATH`, `STORAGE_ROOT_PATH` | Yes | Synology/NFS mount → `/app/storage` |
| `POSTGRES_PORT` | Optional | Default 5000 |

### 1.3 Frontend env (env.example.frontend)

| Variable | Required | Notes |
|----------|----------|--------|
| `API_URL` | Yes | What the browser uses: `http://FRONTEND_IP:8000/api/v1` |
| `API_BACKEND_URL` | Yes | Backend reachable from FE server: `http://BACKEND_IP:8001` |

### 1.4 Ports and connectivity

| Port | Service | Where | Firewall |
|------|---------|--------|----------|
| **8000** | Web (Next.js) | Frontend server | Open for users (or load balancer) |
| **8001** | API (NestJS) | Backend server | Open from **frontend server IP** only (or same host if single-server) |
| 5000 | Postgres | Backend server | Optional; usually internal only |
| 6379 | Redis | Backend server | Internal only |

### 1.5 Application behaviour

| Check | Notes |
|-------|--------|
| API runs `prisma migrate deploy` on startup | Migrations apply automatically when API container starts |
| Login sets cookie via FE proxy | Frontend must have `API_BACKEND_URL` so `/api/auth/login` and `/api/v1` proxy work; login then redirects to landing |
| CORS | Backend `CORS_ORIGIN` must match the URL users use to open the app (e.g. `http://FRONTEND_IP:8000`) |

### 1.6 Verification result

If all items above are in place, preparation for prod is **complete**. Proceed to Part 2.

---

## Part 2: Step-by-step deploy using PuTTY

You will use **two servers**: one for backend (API + DB + Redis + MinIO), one for frontend (Next.js). You connect from Windows using **PuTTY**.

**Ports:** DB host **5000**, Web **8000**, API **8001**.

---

### Prerequisites (before you start)

- Two Linux servers (e.g. Ubuntu 22.04) with SSH access.
- **Docker** and **Docker Compose** (v2) installed on **both** servers.
- **Git** installed on both servers.
- You know:
  - **Backend server IP** (e.g. `192.168.1.20`)
  - **Frontend server IP** (e.g. `192.168.1.10`)
- Firewall: frontend server can reach backend on port **8001**; users can reach frontend on **8000** (or you will open it after deploy).
- You have decided: branch to deploy (e.g. `main` or `release/prod`). Replace `BRANCH` below with that branch.

---

### Step 1: Connect to the backend server with PuTTY

1. Open **PuTTY**.
2. **Host Name:** backend server IP (e.g. `192.168.1.20`).
3. **Port:** 22.
4. **Connection type:** SSH.
5. Click **Open**. Log in (e.g. with username/password or key).

You should see a shell prompt on the backend server.

---

### Step 2: Install Docker and Docker Compose (backend, if not already)

If Docker is not installed:

```bash
# Ubuntu/Debian example
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a644 /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
# Log out and back in (or new PuTTY session) so docker runs without sudo
```

---

### Step 3: Clone the repo and go to project (backend)

```bash
# Replace with your repo URL and branch
git clone https://github.com/YOUR_ORG/sustainability-portal.git
cd sustainability-portal
git checkout BRANCH
git pull origin BRANCH
```

---

### Step 4: Create and edit `.env` on the backend server

```bash
cd infra
cp env.example.backend .env
nano .env
```

Edit these (replace placeholders with real values and your **frontend** server IP):

- `DB_PASSWORD=your-db-password` → strong password
- `REDIS_PASSWORD=your-redis-password` → strong password
- `JWT_SECRET=...` → strong secret (e.g. from `openssl rand -base64 64`)
- `JWT_REFRESH_SECRET=...` → strong secret
- `JWT_ADMIN_SECRET=...` → strong secret
- `CORS_ORIGIN=http://YOUR_FRONTEND_SERVER_IP:8000` → e.g. `http://192.168.1.10:8000`
- `STORAGE_HOST_PATH=/mnt/nas/slms-docs` and `STORAGE_ROOT_PATH=/app/storage`

Save and exit (in nano: Ctrl+O, Enter, Ctrl+X).

---

### Step 5: Build and start the backend stack

From the **project root** (one level above `infra`):

```bash
cd /path/to/sustainability-portal
chmod +x infra/up-prod-backend.sh
./infra/up-prod-backend.sh up -d --build
```

Use `build --no-cache` only when troubleshooting stale cache or dependency issues.

Wait 30–60 seconds for Postgres, Redis, MinIO, and API to become healthy.

---

### Step 6: Check backend (migrations and health)

```bash
docker compose -f infra/docker-compose.prod.backend.yml logs api --tail 50
```

Look for: migrations applied (if any) and “Nest application successfully started” or “listening on port 3001”.

```bash
curl -s http://localhost:8001/api/v1/health
```

You should get a JSON response with `"status":"ok"`.

Optional – migrate status:

```bash
docker compose -f infra/docker-compose.prod.backend.yml exec api npx prisma migrate status
```

Expected: “Database schema is up to date!”.

Optional – seed (first deploy only, if you need initial admin/policies):

```bash
docker compose -f infra/docker-compose.prod.backend.yml exec api npx prisma db seed
```

---

### Step 7: Open backend port 8001 to the frontend server

On the **backend** server (or in your cloud firewall):

- Allow **inbound TCP 8001** from the **frontend server IP** only.

(If both servers are in the same VPC and no host firewall blocks it, this may already work.)

---

### Step 8: Connect to the frontend server with PuTTY

1. Open a **new** PuTTY session (or disconnect from backend).
2. **Host Name:** frontend server IP (e.g. `192.168.1.10`).
3. **Port:** 22.
4. Click **Open** and log in.

---

### Step 9: Install Docker and Docker Compose (frontend, if not already)

Same as Step 2, but run on the **frontend** server.

---

### Step 10: Clone the repo and go to project (frontend)

Same as Step 3, but on the **frontend** server (same repo and branch).

```bash
git clone https://github.com/YOUR_ORG/sustainability-portal.git
cd sustainability-portal
git checkout BRANCH
git pull origin BRANCH
```

---

### Step 11: Create and edit `.env` on the frontend server

```bash
cd infra
cp env.example.frontend .env
nano .env
```

Set (use **this** server’s IP for `API_URL`, **backend** server’s IP for `API_BACKEND_URL`):

- `API_URL=http://FRONTEND_IP:8000/api/v1`  
  Example: `API_URL=http://192.168.1.10:8000/api/v1`
- `API_BACKEND_URL=http://BACKEND_IP:8001`  
  Example: `API_BACKEND_URL=http://192.168.1.20:8001`

Save and exit.

---

### Step 12: Build and start the frontend

From the **project root** on the frontend server:

```bash
cd /path/to/sustainability-portal
docker compose -f infra/docker-compose.prod.frontend.yml up -d --build
```

The first build can take several minutes.

---

### Step 13: Check frontend

```bash
docker compose -f infra/docker-compose.prod.frontend.yml ps
docker compose -f infra/docker-compose.prod.frontend.yml logs web --tail 30
```

Web should be listening on port 8000.

---

### Step 14: Open frontend port 8000 for users

On the **frontend** server (or cloud firewall):

- Allow **inbound TCP 8000** from the internet (or from your load balancer / VPN).

---

### Step 15: Test in the browser

1. Open: `http://FRONTEND_IP:8000` (e.g. `http://192.168.1.10:8000`).
2. You should see the portal.
3. Try **Login** with a user that exists (or register then login).
4. After login, you should be **redirected to the landing page** (no refresh needed).
5. Try a few pages (e.g. Library, Policies) and admin if you use it.

If login fails or CORS errors appear, re-check:

- Backend `CORS_ORIGIN` = `http://FRONTEND_IP:8000` (no trailing slash).
- Frontend `API_URL` = `http://FRONTEND_IP:8000/api/v1` and `API_BACKEND_URL` = `http://BACKEND_IP:8001`.

---

## Ensuring Compose loads the correct env file

To avoid “variable is not set” warnings and ensure secrets are always loaded:

**Option 1 – Use the wrapper scripts (recommended)**  
Scripts resolve the env file path from the repo, so it works no matter where you run them:

```bash
# Backend (from repo root; requires infra/env.prod.backend)
chmod +x infra/up-prod-backend.sh
./infra/up-prod-backend.sh up -d --build

# Frontend (requires infra/env.prod.frontend)
chmod +x infra/up-prod-frontend.sh
./infra/up-prod-frontend.sh up -d --build
```

**Option 2 – Manual with --env-file**  
Run from the **project root** (the directory that contains `infra/`) and pass the env file explicitly:

```bash
cd /path/to/sustainability-portal
docker compose --env-file infra/env.prod.backend -f infra/docker-compose.prod.backend.yml up -d --build
```

If you run from inside `infra/`, the path must not include `infra/`:  
`docker compose --env-file env.prod.backend -f docker-compose.prod.backend.yml up -d --build`

---

## Quick reference – commands by server

**Backend server**

```bash
cd /path/to/sustainability-portal
cp infra/env.example.backend infra/env.prod.backend
# Edit infra/env.prod.backend (DB_*, REDIS_*, JWT_*, CORS_ORIGIN, STORAGE_*)
chmod +x infra/up-prod-backend.sh
./infra/up-prod-backend.sh up -d --build
./infra/up-prod-backend.sh logs api --tail 50
curl -s http://localhost:8001/api/v1/health
```

**Frontend server**

```bash
cd /path/to/sustainability-portal
cp infra/env.example.frontend infra/env.prod.frontend
# Edit infra/env.prod.frontend (API_URL, API_BACKEND_URL with correct IPs)
chmod +x infra/up-prod-frontend.sh
./infra/up-prod-frontend.sh up -d --build web
./infra/up-prod-frontend.sh logs web --tail 30
```

---

## Routine deploy vs troubleshooting

**Routine deploy (after `git pull`)** — uses Docker layer cache; much faster and lighter on disk/bandwidth:

```bash
./infra/up-prod-backend.sh up -d --build api
./infra/up-prod-frontend.sh up -d --build web
```

**Only when troubleshooting** (stale cache, dependency weirdness):

```bash
./infra/up-prod-backend.sh build --no-cache api
./infra/up-prod-backend.sh up -d api

./infra/up-prod-frontend.sh build --no-cache web
./infra/up-prod-frontend.sh up -d web
```

**Low disk on server:** `./infra/clean-dev-cache.sh` (or `--aggressive` to remove unused images).

**Low RAM during frontend build:** set `BUILD_LOW_MEMORY=1` in `infra/env.prod.frontend` (optional `NODE_OPTIONS=--max-old-space-size=1024`).

---

## Later: switching from IP to domain

When you have a domain:

1. **Backend** `infra/.env`: set `CORS_ORIGIN=https://your-domain.com` (or `https://app.your-domain.com`).
2. **Frontend** `infra/.env`: set `API_URL=https://your-domain.com/api/v1` and keep `API_BACKEND_URL` as the internal backend URL (e.g. `http://BACKEND_IP:8001` or internal hostname).
3. Put a reverse proxy (e.g. Nginx) in front of the frontend on 443 and optionally in front of the API.
4. Rebuild/restart frontend after changing `API_URL`:  
   `docker compose -f infra/docker-compose.prod.frontend.yml up -d --build`

---

## Troubleshooting

| Problem | What to check |
|--------|----------------|
| **Connection timeout to DB** (pgAdmin/DBeaver) | Timeout = network/firewall, not wrong password. **Local Docker Postgres:** (1) `docker compose -f infra/docker-compose.prod.backend.yml ps` — postgres must be Up. (2) Port: `POSTGRES_PORT` (example: **5000**). (3) Security group must allow your client IP to that port. (4) Outside the VPC: SSH tunnel `ssh -L 5000:BACKEND_PRIVATE_IP:5000 user@<backend-public-ip>`. **ApsaraDB:** connect to the RDS internal/public endpoint; whitelist your IP. See [MIGRATE-TO-APSARA-DB.md](./MIGRATE-TO-APSARA-DB.md). |
| API container exits | `docker compose -f infra/docker-compose.prod.backend.yml logs api`. Check `DATABASE_URL` (or `DB_HOST` / `DB_*`), `REDIS_*`, `JWT_*` in the backend env file. |
| Migrations fail | `docker compose -f infra/docker-compose.prod.backend.yml exec api npx prisma migrate status`. Ensure the target DB (local Postgres or ApsaraDB) is reachable and `DATABASE_URL` is correct. |
| Frontend cannot reach API | From frontend server: `curl -s http://BACKEND_IP:8001/api/v1/health`. Open port 8001 from frontend to backend. |
| Login does not redirect | Frontend must have `API_BACKEND_URL=http://BACKEND_IP:8001` so the login route and proxy work. Rebuild frontend after changing: `docker compose -f infra/docker-compose.prod.frontend.yml up -d --build`. |
| CORS errors in browser | Backend `CORS_ORIGIN` must exactly match the URL in the address bar (e.g. `http://FRONTEND_IP:8000`). |

For more detail on env vars and architecture, see `infra/env.example.backend`, `infra/env.example.frontend`, and `infra/docker-compose.prod.*.yml`.
