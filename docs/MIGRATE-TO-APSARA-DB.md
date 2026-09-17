# Migrate SLMS Postgres to ApsaraDB RDS (PostgreSQL 18)

Dump the Docker **PostgreSQL 16** `slms` database on the backend ECS and restore it onto **ApsaraDB RDS PostgreSQL 18**. Redis and document files stay on the backend host. Frontend does not talk to Postgres.

**Run Dev first**, prove dump/restore/cutover/rollback, then repeat on Prod in a maintenance window.

Do **not** share one ApsaraDB database between Dev and Prod.

| Env | Backend compose | Source Docker Postgres | Typical host port |
|-----|-----------------|------------------------|-------------------|
| Dev | `infra/docker-compose.dev.backend.yml` (ECS `172.28.92.57`) | service `postgres` | `5432` (`POSTGRES_PORT`) |
| Prod | `infra/docker-compose.prod.backend.yml` | `slms-postgres-prod` | `5000` (`POSTGRES_PORT`) |

Laptop local compose (`infra/docker-compose.yml`) stays on Docker Postgres 16.

Official references:

- [Alibaba: pg_dump / pg_restore into RDS for PostgreSQL](https://www.alibabacloud.com/help/en/rds/apsaradb-rds-for-postgresql/migrate-data-from-a-self-managed-postgresql-database-to-an-apsaradb-rds-for-postgresql-instance-by-using-pg-dump-and-pg-restore)
- [PostgreSQL 18: upgrading across major versions](https://www.postgresql.org/docs/18/upgrading.html)

---

## 1. Pre-flight (do this before any dump)

### 1.1 ApsaraDB instance

- Engine is **PostgreSQL 18**. Source remains Docker **PostgreSQL 16**. A 16 → 18 logical restore is supported; 18 → 16 is not.
- Separate **instance** (preferred) or at least separate **databases** for Dev and Prod.
- Same **VPC and region** as the backend ECS. Use the **internal** endpoint, not public.
- Privileged account exists. Empty target database created (name `slms` unless you chose otherwise).
- IP whitelist (or ECS security-group attach) includes the backend private IP:
  - Dev: `172.28.92.57`
  - Prod: backend private IP
- Prefer attaching the ECS security group over `0.0.0.0/0`.

### 1.2 Network and SSL from the backend host

```bash
nc -vz <RDS_INTERNAL_HOST> 5432
```

If RDS requires SSL, the API `DATABASE_URL` must include `sslmode=require` (or `verify-ca` / `verify-full` plus a CA file). URL-encode special characters in the password (`@` → `%40`, `#` → `%23`, `/` → `%2F`, `%` → `%25`). Quote the whole URL in the env file.

### 1.3 Extensions

As the privileged ApsaraDB user, on the empty `slms` database:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

Required by Prisma migration `20260226100000_refresh_token_store_hash`.

### 1.4 PostgreSQL 18 client tools

Do **not** dump with the `postgres:16` container’s `pg_dump`, and do **not** restore with `postgresql-client-16`. Custom-format archives are not backward compatible.

Use **PostgreSQL 18** clients for both dump and restore (`postgres:18` image or `postgresql-client-18`):

```bash
docker run --rm postgres:18 pg_dump --version
docker run --rm postgres:18 pg_restore --version
```

Both must report **18.x**.

### 1.5 Source size (estimate downtime)

Dev:

```bash
docker compose --env-file infra/.env -f infra/docker-compose.dev.backend.yml exec postgres \
  psql -U slms -d slms -c "SELECT pg_size_pretty(pg_database_size('slms'));"
```

Prod (use `infra/env.prod.backend` or `./infra/up-prod-backend.sh`):

```bash
./infra/up-prod-backend.sh exec postgres \
  psql -U slms -d slms -c "SELECT pg_size_pretty(pg_database_size('slms'));"
```

### 1.6 What is not migrated

- Redis (cache / queues) — leave on the backend host.
- Document bytes under `STORAGE_HOST_PATH` — only `file_key` lives in Postgres.
- Do **not** run `prisma db seed` after restore (it would duplicate baseline rows).

---

## 2. Dump and restore

Freeze writes for a consistent dump. Announce a short maintenance window.

Replace compose/env as needed. Examples below use **Dev**. For Prod, use `docker-compose.prod.backend.yml` / `./infra/up-prod-backend.sh` and source port **`5000`** (or your `POSTGRES_PORT`).

### 2.1 Stop the API only (leave source Postgres up)

```bash
cd /path/to/sustainability-portal
./infra/up-dev-backend.sh stop api
```

Prod:

```bash
./infra/up-prod-backend.sh stop api
```

### 2.2 Dump with a PostgreSQL 18 client

Connect to the still-running Docker Postgres on the **host** port. Do not `exec pg_dump` inside the `postgres:16` container.

Do **not** `source` / `. infra/.env`. Compose env files are not shell syntax; `&`, `$`, `#`, or `@` in passwords will run as commands.

Read DB credentials from the **running** Postgres container instead:

```bash
# Dev — from /opt/slmsBE (or repo root)
DB_USER=$(./infra/up-dev-backend.sh exec -T postgres printenv POSTGRES_USER)
DB_NAME=$(./infra/up-dev-backend.sh exec -T postgres printenv POSTGRES_DB)
DB_PASSWORD=$(./infra/up-dev-backend.sh exec -T postgres printenv POSTGRES_PASSWORD)

# Prod: use ./infra/up-prod-backend.sh instead of up-dev-backend.sh

DUMP=/tmp/slms.dump

# Host port: Dev usually 5432, Prod usually 5000. Confirm with: ss -lntp | grep 5432
docker run --rm --network host \
  -e PGPASSWORD="$DB_PASSWORD" \
  -v /tmp:/dump \
  postgres:18 \
  pg_dump -h 127.0.0.1 -p 5432 -U "$DB_USER" -d "$DB_NAME" \
  -Fc --no-owner --no-acl --no-tablespaces --quote-all-identifiers \
  -f /dump/slms.dump

ls -lh /tmp/slms.dump
```

`--quote-all-identifiers` reduces reserved-word surprises between 16 and 18. `--no-owner --no-acl --no-tablespaces` is required because RDS accounts are not superusers.

### 2.3 Restore into ApsaraDB with the same PG 18 client

Target database must be **empty** (no prior `prisma migrate deploy`). Enable `pgcrypto` first (section 1.3).

```bash
# Confirm the dump exists first. Do not use $DUMP if you opened a new shell.
ls -lh /tmp/slms.dump

docker run --rm --network host \
  -e PGPASSWORD="$APSARA_PASSWORD" \
  -v /tmp/slms.dump:/tmp/slms.dump:ro \
  postgres:18 \
  pg_restore -h "$RDS_INTERNAL_HOST" -p 5432 -U "$APSARA_USER" -d slms \
  --no-owner --no-acl --no-tablespaces --single-transaction \
  /tmp/slms.dump
```

If `--single-transaction` fails on extension or ACL noise, drop that flag and restore into a **freshly emptied** database.

### 2.4 Spot-check

Compare row counts on source (Docker, still stopped for writes) and ApsaraDB:

```sql
SELECT version();  -- must show PostgreSQL 18 on ApsaraDB
SELECT extname FROM pg_extension WHERE extname = 'pgcrypto';
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM documents;
SELECT COUNT(*) FROM document_versions;
SELECT COUNT(*) FROM _prisma_migrations;
SELECT migration_name, finished_at FROM _prisma_migrations ORDER BY finished_at;
```

Every `_prisma_migrations` row should have `finished_at` set. Keep the dump file and the Docker `postgres_data` volume. Do **not** run `docker compose down -v`.

---

## 3. Cutover (point the API at ApsaraDB)

Compose already accepts a full `DATABASE_URL`. The API no longer waits for the local Postgres container (entrypoint retries `prisma migrate deploy`). Redis `depends_on` is unchanged.

### 3.1 Set env on the backend host

Edit `infra/.env` / `infra/.env.be.dev` (Dev) or `infra/env.prod.backend` (Prod). Prefer a **full** URL so SSL and password encoding are explicit:

```bash
DB_HOST=pgm-xxxx.pgsql.<region>.rds.aliyuncs.com
DB_PORT=5432
# Quote the URL. URL-encode special characters in the password.
DATABASE_URL="postgresql://slms:<urlencoded-password>@pgm-xxxx.pgsql.<region>.rds.aliyuncs.com:5432/slms?schema=public&sslmode=require"
```

Leave `DB_USER` / `DB_PASSWORD` / `DB_NAME` as-is if you still need them for a local Postgres rollback.

If `DATABASE_URL` is unset, compose builds:

`postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST:-postgres}:${DB_PORT:-5432}/${DB_NAME}?schema=public`

That constructed form does **not** add `sslmode` and does **not** URL-encode the password. Use the full `DATABASE_URL` for ApsaraDB.

### 3.2 Recreate the API only

```bash
# Dev
./infra/up-dev-backend.sh up -d --build api

# Prod
./infra/up-prod-backend.sh up -d --build api
```

Do **not** run a bare `up -d` after you intend to leave local Postgres stopped — that starts the `postgres` service again. After cutover, start only `redis` and `api` (`up -d redis api`).

### 3.3 Confirm logs

```bash
./infra/up-dev-backend.sh logs api
```

Expect `prisma migrate deploy` to report the schema already up to date (restore included `_prisma_migrations`). Then the API listens as usual.

---

## 4. Verification

- On ApsaraDB: `SELECT version();` shows PostgreSQL 18.
- `GET /api/v1/health` (Dev: `http://172.28.92.57:3001/api/v1/health`, Prod: host port `8001`) reports the database connected.
- Inside the API container: `npx prisma migrate status` — no pending or failed migrations.
- Login (admin and SSO if enabled) works. Password hashes and `oidc_sub` live in Postgres.
- Open a document; download still works (files stay on NAS / `STORAGE_HOST_PATH`).
- Create or edit one record; confirm the new row on **ApsaraDB**, not in the old Docker container.
- Audit log write succeeds (JSON columns).
- Frontend needs no change if `API_URL` is unchanged.
- Dev and Prod each use their **own** ApsaraDB database.

---

## 5. Decommission local Docker Postgres (after soak)

- Dev: wait 24–48 hours. Prod: at least one backup cycle or one business day.
- Stop Postgres, keep the volume:

```bash
./infra/up-dev-backend.sh stop postgres
```

- Close host port `5432` / `5000` in the ECS security group (that mapping was only for the old container).
- Later deploys: `up -d redis api` (or `up -d --build api`). Do not `up -d` until the `postgres` service is removed from the server compose file.
- Keep the `postgres_data` volume until rollback is no longer needed, then delete it explicitly (`docker volume rm …`). Never use `down -v` while you still want rollback.

---

## 6. Rollback

Rollback is **switch the API back to the untouched Docker PostgreSQL 16 volume**. Do not `pg_restore` an ApsaraDB 18 dump onto the old PG 16 container.

1. Comment out or remove `DATABASE_URL` and set `DB_HOST=postgres`, `DB_PORT=5432` (container port; compose default).
2. Start local Postgres and the API:

```bash
./infra/up-dev-backend.sh up -d postgres api
```

3. Rows written only to ApsaraDB after cutover are not in the old volume. Replay them manually or accept that soak-window data is lost.

---

## 7. Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| `pg_restore: unsupported version in file header` | Dump was taken with a newer client than the restore client, or the opposite mismatch. Use **18.x** for both. |
| Permission / owner errors on restore | Missing `--no-owner --no-acl --no-tablespaces`, or not using a privileged RDS account. |
| `pgcrypto` / `digest` errors | Extension not created on the empty target before restore, or restore skipped it. |
| API cannot reach DB / whitelist timeout | Backend private IP not on the RDS whitelist, or using the public endpoint from inside the VPC. |
| SSL / `pg_hba` / certificate errors | Add `sslmode=require` (or verify-ca) to `DATABASE_URL`. |
| `command not found` / `&` / `email` after `. infra/.env` | Do not source the env file. `&` in `SMTP_PASS` or other values is executed as a background job. Read `POSTGRES_*` from the running container instead. |
| Prisma P1000 / password auth failed | Password not URL-encoded in `DATABASE_URL`, or env file truncated at `#` / `@`. |
| `prisma migrate deploy` reapplies or fails after restore | Target was not empty, or `_prisma_migrations` was omitted. Drop/recreate the ApsaraDB database and restore again. |
| Seed duplicated users/roles | `prisma db seed` was run after restore. Do not seed. |
| Local Postgres comes back after deploy | A bare `up -d` was used. Use `up -d redis api` after cutover. |
