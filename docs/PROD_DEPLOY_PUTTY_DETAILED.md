# Production deploy – detailed step-by-step with PuTTY

This guide walks you through deploying the Sustainability Portal to **two production servers** (backend and frontend) using **PuTTY** from Windows. Every step is spelled out so you can follow it even if you rarely use the command line.

**Ports used:** DB **5000**, Web **8000**, API **8001**.

---

## Before you start – gather this information

Fill this in and keep it handy (use Notepad or this table):

| What | Your value | Example |
|------|------------|---------|
| Backend server IP | _____________ | 192.168.1.20 |
| Frontend server IP | _____________ | 192.168.1.10 |
| SSH username (backend) | _____________ | ubuntu or root |
| SSH username (frontend) | _____________ | ubuntu or root |
| Git branch to deploy | _____________ | dev or main |
| Repository URL | _____________ | https://github.com/YOUR_ORG/sustainability-portal.git |

**You will need:**

- PuTTY installed on Windows ([download](https://www.putty.org/)).
- SSH access to both servers (password or private key).
- If using a key: PuTTY format (`.ppk`). In PuTTY: Connection → SSH → Auth → Private key file.

---

# Part A: Backend server

---

## A1. Open PuTTY and connect to the backend server

1. **Start PuTTY** (double‑click `putty.exe`).
2. In the left tree, make sure **Session** is selected.
3. **Host Name (or IP address):** type the **backend server IP** (e.g. `192.168.1.20`).
4. **Port:** `22`.
5. **Connection type:** **SSH** (should be selected).
6. (Optional) Under **Saved Sessions** type a name like `Prod Backend` and click **Save** so you can load it next time.
7. Click **Open**.
8. If a security alert appears (“host key not in cache”), click **Accept**.
9. When prompted:
   - **login as:** type your SSH username (e.g. `ubuntu`) and press Enter.
   - **password:** type your SSH password (nothing will appear) and press Enter.

**You should see:** A black window with a prompt such as `ubuntu@backend-server:~$` or `root@hostname:~#`. You are now in a shell on the backend server.

---

## A2. (Optional) Install Git if it is not installed

Run:

```bash
git --version
```

- If you see something like `git version 2.34.1`, skip to **A3**.
- If you see `command not found`, install Git:

**On Ubuntu/Debian:**

```bash
sudo apt-get update
sudo apt-get install -y git
```

Enter your password if asked. Then run `git --version` again to confirm.

---

## A3. Install Docker and Docker Compose (if not already installed)

Run:

```bash
docker --version
docker compose version
```

- If both commands show a version (e.g. `Docker version 24.0.x` and `Docker Compose version v2.x`), skip to **A4**.
- If either fails, install Docker and Compose as below.

**On Ubuntu 22.04 / Debian (copy and paste the whole block):**

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a644 /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
```

Then **close PuTTY and open a new session** to the same server (same as A1) and log in again. This is so your user is in the `docker` group. After reconnecting, run:

```bash
docker run hello-world
```

**You should see:** A short message ending with “Hello from Docker!”. Then you can remove the test container:

```bash
docker rm $(docker ps -aq --filter ancestor=hello-world) 2>/dev/null; true
```

---

## A4. Choose a folder and clone the repository

Decide where the project will live. Common choice: your home directory.

**Example: home directory**

```bash
cd ~
pwd
```

**You should see:** something like `/home/ubuntu` or `/root`.

Clone the repo (replace the URL and branch with yours):

```bash
git clone https://github.com/YOUR_ORG/sustainability-portal.git
cd sustainability-portal
git checkout dev
git pull origin dev
```

- Replace `https://github.com/YOUR_ORG/sustainability-portal.git` with your actual repository URL.
- Replace `dev` with your branch (e.g. `main`).

**You should see:** “Cloning into 'sustainability-portal'...” and then a list of files. No “fatal” or “error” messages.

Check that the compose file exists:

```bash
ls -la infra/docker-compose.prod.backend.yml infra/env.example.backend
```

**You should see:** Two lines showing both files (no “No such file”).

---

## A5. Create the backend `.env` file from the example

```bash
cd ~/sustainability-portal/infra
cp env.example.backend .env
ls -la .env
```

**You should see:** `.env` listed. Do **not** share this file or commit it; it will hold secrets.

---

## A6. Generate strong secrets (on the server)

Run these one by one and **write down** each output (you will paste them into `.env` in the next step):

```bash
openssl rand -base64 48
```

Copy the line it prints (e.g. `K7x...==`). Run it **three more times** so you have four different values. Use them for:

1. `JWT_SECRET`
2. `JWT_REFRESH_SECRET`
3. `JWT_ADMIN_SECRET`
4. (optional) one for `DB_PASSWORD`, one for `REDIS_PASSWORD`, or generate more with the same command.

Example (run multiple times):

```bash
openssl rand -base64 48
openssl rand -base64 48
openssl rand -base64 48
openssl rand -base64 48
```

Keep a temporary note of which value you will use for which variable.

---

## A7. Edit the backend `.env` file with `nano`

Open the file:

```bash
nano .env
```

**You should see:** The contents of `env.example.backend` in the editor.

**Edit these lines** (use arrow keys to move, type to replace):

1. **DB_PASSWORD**  
   Replace `your-db-password` with a strong password (e.g. one of the values you generated).

2. **REDIS_PASSWORD**  
   Replace `your-redis-password` with another strong value.

3. **JWT_SECRET**  
   Replace with the first value from `openssl rand -base64 48`.

4. **JWT_REFRESH_SECRET**  
   Replace with the second value.

5. **JWT_ADMIN_SECRET**  
   Replace with the third value.

6. **CORS_ORIGIN**  
   Replace `YOUR_FRONTEND_SERVER_IP` with the **frontend** server IP and keep the port `:8000`.  
   Example: `CORS_ORIGIN=http://192.168.1.10:8000`  
   No trailing slash.

7. **STORAGE_HOST_PATH** and **STORAGE_ROOT_PATH**  
   Point at the Synology (or local) mount, e.g. `STORAGE_HOST_PATH=/mnt/nas/slms-docs` and `STORAGE_ROOT_PATH=/app/storage`.

**Save and exit in nano:**

1. Press **Ctrl+O** (to write/save).
2. Press **Enter** to confirm the filename.
3. Press **Ctrl+X** to exit.

**You should see:** You are back at the shell prompt.

Double-check that secrets are set (do not paste this output anywhere public):

```bash
grep -E "^(DB_PASSWORD|JWT_SECRET|CORS_ORIGIN)=" .env
```

You should see your values (CORS_ORIGIN with the frontend IP and `:8000`).

---

## A8. Build and start the backend stack

Go to the project root and run compose (paths assume project is in `~/sustainability-portal`):

```bash
cd ~/sustainability-portal
chmod +x infra/up-prod-backend.sh
./infra/up-prod-backend.sh up -d --build
```

**You should see:** Build output (reuses Docker cache on later deploys). Wait until it finishes without errors. First build can take several minutes; routine deploys are faster.

Use `build --no-cache` only when troubleshooting stale cache or dependency issues.

Wait about 60 seconds for the API to run migrations and start.

---

## A9. Check that the backend is running

List containers:

```bash
docker compose -f infra/docker-compose.prod.backend.yml ps
```

**You should see:** All services “Up” (postgres, redis, api). After ApsaraDB cutover, postgres may be stopped.

View API logs:

```bash
docker compose -f infra/docker-compose.prod.backend.yml logs api --tail 80
```

**You should see:**  
- Lines like “Applying migration …” (if there were pending migrations).  
- Then “Nest application successfully started” or “listening on port 3001”.

Health check:

```bash
curl -s http://localhost:8001/api/v1/health
```

**You should see:** A single line of JSON containing `"status":"ok"`.

If you see “Connection refused”, wait a bit and run the same `curl` again. If it still fails, run the `logs api` command again and look for errors (e.g. database or Redis connection).

**(Optional)** Check migration status:

```bash
docker compose -f infra/docker-compose.prod.backend.yml exec api npx prisma migrate status
```

**You should see:** “Database schema is up to date!”.

**(Optional, first deploy only)** Seed initial data (admin user, policies, etc.):

```bash
docker compose -f infra/docker-compose.prod.backend.yml exec api npx prisma db seed
```

---

## A10. Open port 8001 on the backend (firewall)

The frontend server must be able to reach this server on port **8001**.

**If you use UFW (Ubuntu):**

```bash
sudo ufw allow from FRONTEND_SERVER_IP to any port 8001
sudo ufw status
```

Replace `FRONTEND_SERVER_IP` with the actual frontend IP (e.g. `192.168.1.10`). If you need to enable UFW:

```bash
sudo ufw enable
```

**If you use a cloud firewall (AWS Security Group, Azure NSG, etc.):** Add an inbound rule: TCP port **8001**, source = frontend server IP.

Backend is done. You can leave this PuTTY window open or disconnect.

---

# Part B: Frontend server

---

## B1. Connect to the frontend server with PuTTY

1. Open a **new** PuTTY window (or disconnect from the backend and start again).
2. **Host Name:** **frontend server IP** (e.g. `192.168.1.10`).
3. **Port:** `22`.
4. **Connection type:** SSH.
5. Click **Open**, accept the host key if asked, and log in (username + password or key).

**You should see:** A shell prompt on the frontend server (e.g. `ubuntu@frontend-server:~$`).

---

## B2. Install Git and Docker (if needed)

Same as on the backend:

- **Git:** `git --version`. If missing: `sudo apt-get update && sudo apt-get install -y git`
- **Docker:** `docker --version` and `docker compose version`. If missing, use the same Docker install block as in **A3**, then **close and reopen PuTTY** and run `docker run hello-world`.

---

## B3. Clone the repository on the frontend

Use the **same** repo URL and branch as on the backend:

```bash
cd ~
git clone https://github.com/YOUR_ORG/sustainability-portal.git
cd sustainability-portal
git checkout dev
git pull origin dev
```

Replace the URL and `dev` with your repo and branch. Then:

```bash
ls -la infra/docker-compose.prod.frontend.yml infra/env.example.frontend
```

**You should see:** Both files listed.

---

## B4. Create and edit the frontend `.env` file

```bash
cd ~/sustainability-portal/infra
cp env.example.frontend .env
nano .env
```

**Edit exactly two values:**

1. **API_URL**  
   Must be the **frontend** server URL and port **8000**, plus `/api/v1`.  
   Example (replace with your frontend IP):  
   `API_URL=http://192.168.1.10:8000/api/v1`

2. **API_BACKEND_URL**  
   Must be the **backend** server IP and port **8001**.  
   Example (replace with your backend IP):  
   `API_BACKEND_URL=http://192.168.1.20:8001`

No trailing slashes. Save and exit: **Ctrl+O**, **Enter**, **Ctrl+X**.

Verify:

```bash
grep -E "^(API_URL|API_BACKEND_URL)=" .env
```

**You should see:** Your two URLs with the correct IPs and ports (8000 for API_URL, 8001 for API_BACKEND_URL).

---

## B5. Build and start the frontend

```bash
cd ~/sustainability-portal
docker compose -f infra/docker-compose.prod.frontend.yml up -d --build
```

**You should see:** Build output (Next.js, etc.), then “Creating slms-web-prod … done”. The first build can take 5–15 minutes.

---

## B6. Check that the frontend is running

```bash
docker compose -f infra/docker-compose.prod.frontend.yml ps
docker compose -f infra/docker-compose.prod.frontend.yml logs web --tail 30
```

**You should see:** Container “Up” and logs showing the Next.js server running (e.g. “Ready on port 3000” inside the container; that is mapped to **8000** on the host).

---

## B7. Open port 8000 for users (firewall)

So users (or a load balancer) can reach the portal:

**UFW (Ubuntu):**

```bash
sudo ufw allow 8000/tcp
sudo ufw status
```

**Cloud firewall:** Add inbound rule TCP **8000** from the appropriate source (e.g. 0.0.0.0/0 or your office IP).

---

# Part C: Test in the browser

1. On your Windows PC, open a browser.
2. Go to: **http://FRONTEND_IP:8000** (e.g. `http://192.168.1.10:8000`).
3. You should see the Sustainability Portal (login page or home).
4. Try **Login** with a user that exists (or register first).
5. After a successful login, you should be **redirected to the landing page** without refreshing.
6. Open a few pages (e.g. Library, Policies). If you seeded admin, try the admin area.

**If login does not redirect or you see CORS errors:**

- Backend `infra/.env`: `CORS_ORIGIN` must be exactly `http://FRONTEND_IP:8000` (no trailing slash).
- Frontend `infra/.env`: `API_URL=http://FRONTEND_IP:8000/api/v1` and `API_BACKEND_URL=http://BACKEND_IP:8001`.
- After changing `.env`, rebuild frontend:  
  `docker compose -f infra/docker-compose.prod.frontend.yml up -d --build`

**If the page does not load at all:**

- Check firewall: port 8000 open on the frontend server.
- From your PC: `curl -s -o /dev/null -w "%{http_code}" http://FRONTEND_IP:8000` (PowerShell or WSL). You should get 200.

---

# Copy-paste summary (replace placeholders)

**Backend server (one-time setup + deploy):**

```bash
# Replace REPO_URL and BRANCH
cd ~
git clone REPO_URL sustainability-portal
cd sustainability-portal
git checkout BRANCH
git pull origin BRANCH

cd infra
cp env.example.backend .env
nano .env
# Edit: DB_PASSWORD, REDIS_PASSWORD, JWT_SECRET, JWT_REFRESH_SECRET, JWT_ADMIN_SECRET, CORS_ORIGIN (http://FRONTEND_IP:8000), STORAGE_HOST_PATH. Save: Ctrl+O, Enter, Ctrl+X.

cd ~/sustainability-portal
chmod +x infra/up-prod-backend.sh
./infra/up-prod-backend.sh up -d --build
# Wait ~60s then:
docker compose -f infra/docker-compose.prod.backend.yml logs api --tail 50
curl -s http://localhost:8001/api/v1/health
```

**Frontend server (one-time setup + deploy):**

```bash
# Replace REPO_URL and BRANCH
cd ~
git clone REPO_URL sustainability-portal
cd sustainability-portal
git checkout BRANCH
git pull origin BRANCH

cd infra
cp env.example.frontend .env
nano .env
# Edit: API_URL=http://FRONTEND_IP:8000/api/v1, API_BACKEND_URL=http://BACKEND_IP:8001. Save: Ctrl+O, Enter, Ctrl+X.

cd ~/sustainability-portal
docker compose -f infra/docker-compose.prod.frontend.yml up -d --build
docker compose -f infra/docker-compose.prod.frontend.yml logs web --tail 30
```

---

# Troubleshooting

| Symptom | What to do |
|--------|------------|
| **PuTTY: “Connection refused”** | Check server IP, port 22, and that SSH is running on the server. |
| **“Permission denied (publickey)”** | Use password auth or load the correct .ppk in PuTTY (Connection → SSH → Auth). |
| **`git: command not found`** | Install Git (see A2). |
| **`docker: command not found`** | Install Docker (see A3); then log out and back in. |
| **API container exits** | Run `docker compose -f infra/docker-compose.prod.backend.yml logs api` and fix the reported error (often wrong DB/REDIS/JWT in `.env`). |
| **`curl localhost:8001` connection refused** | Wait longer; API may still be starting or running migrations. Check `logs api` again. |
| **Frontend build fails** | Ensure enough disk and memory. Run `./infra/up-prod-frontend.sh up -d --build web` (cached). If still failing, try `build --no-cache web` and read the last error lines. Run `./infra/clean-dev-cache.sh` if disk is full. |
| **Browser: “This site can’t be reached”** | Open port 8000 on the frontend (B7) and confirm you use `http://FRONTEND_IP:8000`. |
| **Login works but no redirect** | Set `API_BACKEND_URL=http://BACKEND_IP:8001` in frontend `infra/.env`, then `docker compose -f infra/docker-compose.prod.frontend.yml up -d --build`. |
| **CORS error in browser** | Set backend `CORS_ORIGIN=http://FRONTEND_IP:8000` (same as the URL in the address bar, no trailing slash). |

---

# Updating the app later (after code changes)

**Backend:**

```bash
cd ~/sustainability-portal
git pull origin BRANCH
chmod +x infra/up-prod-backend.sh
./infra/up-prod-backend.sh up -d --build api
./infra/up-prod-backend.sh logs api --tail 30
```

**Frontend:**

```bash
cd ~/sustainability-portal
git pull origin BRANCH
chmod +x infra/up-prod-frontend.sh
./infra/up-prod-frontend.sh up -d --build web
./infra/up-prod-frontend.sh logs web --tail 20
```

You do **not** need to recreate `.env` when updating; only change it when you change IPs, ports, or secrets.
