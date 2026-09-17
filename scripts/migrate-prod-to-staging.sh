#!/usr/bin/env bash
# Dump production PostgreSQL and restore it onto staging (Dev backend).
#
# In this repo, staging is the Dev stack:
#   compose  infra/docker-compose.dev.backend.yml
#   project  slms-dev-backend
#   env      infra/.env.be.dev (fallback infra/.env)
#
# Production:
#   compose  infra/docker-compose.prod.backend.yml
#   project  slms-prod-backend
#   env      infra/env.prod.backend
#
# Run dump on the production host. Run restore on the staging host.
# Never point restore at a compose project / env file / RDS host that looks like production.
#
# Dump and restore always use a PostgreSQL 18 client (postgres:18). Do not use the
# postgres:16 container's pg_dump/pg_restore. See docs/MIGRATE-TO-APSARA-DB.md.
#
# Usage:
#   ./scripts/migrate-prod-to-staging.sh dump
#   ./scripts/migrate-prod-to-staging.sh restore /path/to/backup_production_YYYYMMDD_HHMMSS.sql.gz
#   ./scripts/migrate-prod-to-staging.sh verify
#
# Optional env:
#   PROD_COMPOSE_FILE / PROD_PROJECT / PROD_ENV_FILE
#   STAGING_COMPOSE_FILE / STAGING_PROJECT / STAGING_ENV_FILE
#   PROD_DATABASE_URL            dump via this URL (ApsaraDB / remote)
#   STAGING_APSARA_DATABASE_URL  restore/verify target after staging RDS cutover
#   PG18_IMAGE                   default: postgres:18
#   BACKUP_DIR                   default: /opt/backups/slms-production
#   STAGING_BACKUP_DIR           default: <repo>/backups
#   CONFIRM                      set to OVERWRITE-STAGING to skip the prompt
#   PGSSLMODE                    default for RDS: require
#
# After restore: do not run prisma db seed (it would duplicate baseline rows).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMAND="${1:-}"
DUMP_PATH="${2:-}"

PROD_PROJECT="${PROD_PROJECT:-slms-prod-backend}"
PROD_COMPOSE_FILE="${PROD_COMPOSE_FILE:-infra/docker-compose.prod.backend.yml}"
PROD_ENV_FILE="${PROD_ENV_FILE:-infra/env.prod.backend}"
STAGING_PROJECT="${STAGING_PROJECT:-slms-dev-backend}"
STAGING_COMPOSE_FILE="${STAGING_COMPOSE_FILE:-infra/docker-compose.dev.backend.yml}"
PG18_IMAGE="${PG18_IMAGE:-postgres:18}"
BACKUP_DIR="${BACKUP_DIR:-/opt/backups/slms-production}"
STAGING_BACKUP_DIR="${STAGING_BACKUP_DIR:-$PROJECT_ROOT/backups}"

log()  { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"; }
die()  { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "$PROJECT_ROOT/$p"
  fi
}

resolve_staging_env() {
  if [[ -n "${STAGING_ENV_FILE:-}" ]]; then
    echo "$STAGING_ENV_FILE"
    return
  fi
  if [[ -f "$PROJECT_ROOT/infra/.env.be.dev" ]]; then
    echo "infra/.env.be.dev"
  elif [[ -f "$PROJECT_ROOT/infra/.env" ]]; then
    echo "infra/.env"
  else
    die "Staging env not found. Create infra/.env.be.dev or infra/.env (see infra/env.example.backend)."
  fi
}

env_get() {
  local key="$1"
  local file="$2"
  file="$(abs_path "$file")"
  [[ -f "$file" ]] || return 0
  # Do not source compose env files: &, $, #, @ in values would run as shell.
  grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -1 \
    | sed -E "s/^[[:space:]]*${key}=//" \
    | sed 's/\r$//' \
    | sed 's/^["'\'']//;s/["'\'']$//' || true
}

url_host() {
  local url="$1"
  [[ -n "$url" ]] || { echo ""; return; }
  if command -v python3 >/dev/null 2>&1; then
    DATABASE_URL="$url" python3 -c "from urllib.parse import urlparse; import os; print(urlparse(os.environ['DATABASE_URL']).hostname or '')"
  elif command -v node >/dev/null 2>&1; then
    DATABASE_URL="$url" node -e "console.log(new URL(process.env.DATABASE_URL).hostname || '')"
  else
    echo "$url" | sed -E 's#^postgres(ql)?://[^@]+@([^:/]+).*#\2#'
  fi
}

# Prisma adds ?schema=public; libpq does not understand that parameter.
libpq_url() {
  local url="$1"
  if command -v python3 >/dev/null 2>&1; then
    DATABASE_URL="$url" python3 -c "
from urllib.parse import urlparse, parse_qsl, urlencode, urlunparse
import os
u = urlparse(os.environ['DATABASE_URL'])
q = [(k, v) for k, v in parse_qsl(u.query, keep_blank_values=True) if k != 'schema']
print(urlunparse(u._replace(query=urlencode(q))))
"
    return
  fi
  echo "$url" | sed -E 's/[?&]schema=[^&]*//g; s/\?&/?/g; s#://([^/]+)/([^?]+)&#://\1/\2?#; s/[?&]$//'
}

redact_url() {
  echo "$1" | sed -E 's#(postgres(ql)?://[^:/?#]+:)[^@]+@#\1***@#'
}

remote_db_url_from_env() {
  local file="$1"
  local override="$2"
  local url host
  url="$override"
  if [[ -z "$url" ]]; then
    url="$(env_get DATABASE_URL "$file")"
  fi
  host="$(url_host "$url")"
  if [[ -n "$url" && -n "$host" && "$host" != "postgres" && "$host" != "localhost" && "$host" != "127.0.0.1" ]]; then
    echo "$url"
  fi
}

staging_rds_url() {
  local url="${STAGING_APSARA_DATABASE_URL:-}"
  if [[ -z "$url" ]]; then
    url="$(env_get STAGING_APSARA_DATABASE_URL "$(resolve_staging_env)")"
  fi
  if [[ -z "$url" ]]; then
    url="$(remote_db_url_from_env "$(resolve_staging_env)" "")"
  fi
  echo "$url"
}

prod_rds_url() {
  remote_db_url_from_env "$PROD_ENV_FILE" "${PROD_DATABASE_URL:-}"
}

pg18_rds_net() {
  if [[ "$(uname -s)" == "Linux" ]]; then
    echo host
  else
    echo bridge
  fi
}

compose() {
  local env_file="$1"
  local compose_file="$2"
  local project="$3"
  shift 3
  local args=(compose -p "$project" -f "$(abs_path "$compose_file")")
  if [[ -f "$(abs_path "$env_file")" ]]; then
    args+=(--env-file "$(abs_path "$env_file")")
  fi
  docker "${args[@]}" "$@"
}

compose_prod() {
  compose "$PROD_ENV_FILE" "$PROD_COMPOSE_FILE" "$PROD_PROJECT" "$@"
}

compose_staging() {
  compose "$(resolve_staging_env)" "$STAGING_COMPOSE_FILE" "$STAGING_PROJECT" "$@"
}

compose_network() {
  local project="$1"
  docker network ls --format '{{.Name}}' | grep -E "^${project}_default$" | head -1 || true
}

container_env() {
  local which="$1"
  local key="$2"
  if [[ "$which" == "prod" ]]; then
    compose_prod exec -T postgres printenv "$key"
  else
    compose_staging exec -T postgres printenv "$key"
  fi
}

postgres_running() {
  local which="$1"
  if [[ "$which" == "prod" ]]; then
    compose_prod ps --status running --services 2>/dev/null | grep -qx postgres
  else
    compose_staging ps --status running --services 2>/dev/null | grep -qx postgres
  fi
}

run_pg18() {
  local network="$1"
  shift
  docker run --rm -i --network "$network" "$@"
}

run_pg18_rds() {
  local url="$1"
  local shell_cmd="$2"
  run_pg18 "$(pg18_rds_net)" \
    -e PGSSLMODE="${PGSSLMODE:-require}" \
    -e DATABASE_URL="$(libpq_url "$url")" \
    "$PG18_IMAGE" \
    sh -c "$shell_cmd"
}

run_pg18_docker_db() {
  local project="$1"
  local user="$2"
  local password="$3"
  local db="$4"
  local shell_cmd="$5"
  local net
  net="$(compose_network "$project")"
  [[ -n "$net" ]] || die "Docker network ${project}_default not found. Is Postgres up?"
  run_pg18 "$net" \
    -e PGPASSWORD="$password" \
    -e PGHOST=postgres \
    -e PGPORT=5432 \
    -e PGUSER="$user" \
    -e PGDATABASE="$db" \
    "$PG18_IMAGE" \
    sh -c "$shell_cmd"
}

ensure_pg18() {
  require_cmd docker
  if ! docker image inspect "$PG18_IMAGE" >/dev/null 2>&1; then
    log "Pulling $PG18_IMAGE (PostgreSQL 18 client)..."
    docker pull "$PG18_IMAGE"
  fi
  local ver
  ver="$(docker run --rm "$PG18_IMAGE" pg_dump --version)"
  echo "$ver" | grep -q ' 18\.' || die "Expected $PG18_IMAGE pg_dump 18.x, got: $ver"
}

assert_not_production_target() {
  local name
  name="$(echo "$STAGING_PROJECT" | tr '[:upper:]' '[:lower:]')"
  if [[ "$name" == *prod* ]]; then
    die "Refusing restore: STAGING_PROJECT='$STAGING_PROJECT' looks like production."
  fi
  name="$(echo "$STAGING_COMPOSE_FILE" | tr '[:upper:]' '[:lower:]')"
  if [[ "$name" == *prod* ]]; then
    die "Refusing restore: STAGING_COMPOSE_FILE='$STAGING_COMPOSE_FILE' looks like production."
  fi
  name="$(echo "$(resolve_staging_env)" | tr '[:upper:]' '[:lower:]')"
  if [[ "$name" == *prod* ]]; then
    die "Refusing restore: staging env '$(resolve_staging_env)' looks like production."
  fi

  local url host
  url="$(staging_rds_url)"
  host="$(url_host "$url" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$host" && "$host" == *prod* && "$host" != *staging* && "$host" != *dev* ]]; then
    die "Refusing restore: RDS host looks like production ($(redact_url "$url"))."
  fi

  local prod_url prod_host
  prod_url="$(prod_rds_url)"
  prod_host="$(url_host "$prod_url" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$prod_host" && -n "$host" && "$prod_host" == "$host" ]]; then
    die "Refusing restore: production and staging DATABASE_URL hosts are the same ($(redact_url "$url"))."
  fi
}

confirm_overwrite() {
  if [[ "${CONFIRM:-}" == "OVERWRITE-STAGING" ]]; then
    return
  fi
  echo
  warn "This will replace the staging database and overwrite existing data."
  read -r -p "Type OVERWRITE-STAGING to continue: " answer
  [[ "$answer" == "OVERWRITE-STAGING" ]] || die "Aborted."
}

count_sql() {
  cat <<'SQL'
SELECT string_agg(format('%s=%s', t.relname, t.n), E'\n' ORDER BY t.relname)
FROM (
  SELECT 'users'::text AS relname, count(*)::bigint AS n FROM users
  UNION ALL SELECT 'admins', count(*) FROM admins
  UNION ALL SELECT 'roles', count(*) FROM roles
  UNION ALL SELECT 'documents', count(*) FROM documents
  UNION ALL SELECT 'document_versions', count(*) FROM document_versions
  UNION ALL SELECT 'certifications', count(*) FROM certifications
  UNION ALL SELECT 'licenses', count(*) FROM licenses
  UNION ALL SELECT 'operational_units', count(*) FROM operational_units
  UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs
  UNION ALL SELECT '_prisma_migrations', count(*) FROM _prisma_migrations
) t;
SQL
}

count_rows_rds() {
  local url="$1"
  run_pg18_rds "$url" 'psql "$DATABASE_URL" -At -v ON_ERROR_STOP=1' <<SQL
$(count_sql)
SQL
}

count_rows_docker() {
  local user password db
  user="$(container_env staging POSTGRES_USER)"
  password="$(container_env staging POSTGRES_PASSWORD)"
  db="$(container_env staging POSTGRES_DB)"
  run_pg18_docker_db "$STAGING_PROJECT" "$user" "$password" "$db" \
    'psql -At -v ON_ERROR_STOP=1' <<SQL
$(count_sql)
SQL
}

cmd_dump() {
  require_cmd gzip
  ensure_pg18
  mkdir -p "$BACKUP_DIR" || die "Cannot create BACKUP_DIR=$BACKUP_DIR"
  local ts outfile rds_url
  ts="$(date +%Y%m%d_%H%M%S)"
  outfile="${BACKUP_DIR}/backup_production_${ts}.sql.gz"
  rds_url="$(prod_rds_url)"

  cd "$PROJECT_ROOT"

  local dump_ok=0
  if [[ -n "$rds_url" ]]; then
    log "Dumping production ApsaraDB ($(redact_url "$rds_url")) with $PG18_IMAGE ..."
    if run_pg18_rds "$rds_url" \
          'pg_dump --dbname="$DATABASE_URL" --no-owner --no-acl --no-tablespaces --quote-all-identifiers --format=plain --encoding=UTF8' \
        | gzip -9 > "$outfile"; then
      dump_ok=1
    fi
  else
    postgres_running prod || die "Production Postgres container is not running, and no remote DATABASE_URL was found. Set PROD_DATABASE_URL or start local Postgres."
    local user password db
    user="$(container_env prod POSTGRES_USER)"
    password="$(container_env prod POSTGRES_PASSWORD)"
    db="$(container_env prod POSTGRES_DB)"
    [[ -n "$user" && -n "$db" && -n "$password" ]] || die "Could not read POSTGRES_* from the production postgres container."
    log "Dumping Docker project '$PROD_PROJECT' database '$db' with $PG18_IMAGE ..."
    if run_pg18_docker_db "$PROD_PROJECT" "$user" "$password" "$db" \
          'pg_dump --no-owner --no-acl --no-tablespaces --quote-all-identifiers --format=plain --encoding=UTF8' \
        | gzip -9 > "$outfile"; then
      dump_ok=1
    fi
  fi

  if [[ "$dump_ok" -ne 1 ]]; then
    rm -f "$outfile"
    die "pg_dump failed"
  fi

  [[ -s "$outfile" ]] || die "Dump file is empty: $outfile"
  log "Dump written: $outfile ($(du -h "$outfile" | cut -f1))"
  echo
  echo "Next: copy to staging, then restore:"
  echo "  scp $outfile user@staging-host:/opt/backups/slms-staging/"
  echo "  CONFIRM=OVERWRITE-STAGING ./scripts/migrate-prod-to-staging.sh restore /opt/backups/slms-staging/$(basename "$outfile")"
}

wipe_public_schema_sql() {
  cat <<'SQL'
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid();
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO CURRENT_USER;
GRANT ALL ON SCHEMA public TO public;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
SQL
}

invalidate_sessions_sql() {
  cat <<'SQL'
TRUNCATE TABLE refresh_tokens;
TRUNCATE TABLE password_reset_tokens;
SQL
}

restore_stream_to_rds() {
  local url="$1"
  case "$DUMP_PATH" in
    *.sql.gz)
      gunzip -c "$DUMP_PATH" | run_pg18_rds "$url" 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1'
      ;;
    *.sql)
      run_pg18_rds "$url" 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1' < "$DUMP_PATH"
      ;;
    *.dump)
      # Custom-format archive: stream via stdin to pg_restore.
      run_pg18_rds "$url" 'pg_restore --dbname="$DATABASE_URL" --no-owner --no-acl --no-tablespaces' < "$DUMP_PATH"
      ;;
    *)
      die "Unsupported dump format. Use .sql, .sql.gz, or .dump"
      ;;
  esac
}

restore_stream_to_docker() {
  local user="$1"
  local password="$2"
  local db="$3"
  case "$DUMP_PATH" in
    *.sql.gz)
      gunzip -c "$DUMP_PATH" | run_pg18_docker_db "$STAGING_PROJECT" "$user" "$password" "$db" \
        'psql -v ON_ERROR_STOP=1'
      ;;
    *.sql)
      run_pg18_docker_db "$STAGING_PROJECT" "$user" "$password" "$db" \
        'psql -v ON_ERROR_STOP=1' < "$DUMP_PATH"
      ;;
    *.dump)
      run_pg18_docker_db "$STAGING_PROJECT" "$user" "$password" "$db" \
        'pg_restore --dbname="$PGDATABASE" --no-owner --no-acl --no-tablespaces' < "$DUMP_PATH"
      ;;
    *)
      die "Unsupported dump format. Use .sql, .sql.gz, or .dump"
      ;;
  esac
}

safety_dump_rds() {
  local url="$1"
  local dest="$2"
  if run_pg18_rds "$url" \
        'pg_dump --dbname="$DATABASE_URL" --no-owner --no-acl --no-tablespaces --format=plain --encoding=UTF8' \
      | gzip -9 > "$dest"; then
    if [[ -s "$dest" ]]; then
      log "Staging safety dump: $(du -h "$dest" | cut -f1)"
      return
    fi
  fi
  warn "Could not dump current staging RDS (empty DB is OK). Continuing."
  rm -f "$dest"
}

safety_dump_docker() {
  local user="$1"
  local password="$2"
  local db="$3"
  local dest="$4"
  if run_pg18_docker_db "$STAGING_PROJECT" "$user" "$password" "$db" \
        'pg_dump --no-owner --no-acl --no-tablespaces --format=plain --encoding=UTF8' \
      | gzip -9 > "$dest"; then
    if [[ -s "$dest" ]]; then
      log "Staging safety dump: $(du -h "$dest" | cut -f1)"
      return
    fi
  fi
  warn "Could not dump current staging (empty DB is OK). Continuing."
  rm -f "$dest"
}

start_staging_api_rds() {
  log "Starting staging redis + api (do not start local Postgres after ApsaraDB cutover)..."
  compose_staging up -d redis api
}

start_staging_api_docker() {
  log "Starting staging api..."
  compose_staging up -d api
}

restore_to_rds() {
  local url="$1"
  local safety
  mkdir -p "$STAGING_BACKUP_DIR"
  safety="${STAGING_BACKUP_DIR}/backup_staging_apsara_before_restore_$(date +%Y%m%d_%H%M%S).sql.gz"

  log "Stopping staging API to drop DB connections..."
  compose_staging stop api || true

  log "Safety dump of current staging RDS -> $safety"
  safety_dump_rds "$url" "$safety" || true

  log "Recreating schema public + pgcrypto on staging ApsaraDB..."
  run_pg18_rds "$url" 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1' <<SQL
$(wipe_public_schema_sql)
SQL

  log "Restoring $DUMP_PATH onto $(redact_url "$url") ..."
  restore_stream_to_rds "$url"

  log "ANALYZE..."
  run_pg18_rds "$url" 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "ANALYZE;"'

  log "Invalidating copied refresh / password-reset tokens..."
  run_pg18_rds "$url" 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1' <<SQL
$(invalidate_sessions_sql)
SQL

  start_staging_api_rds

  echo
  log "Staging RDS row counts:"
  count_rows_rds "$url" || true
}

restore_to_docker() {
  local user password db safety
  mkdir -p "$STAGING_BACKUP_DIR"
  safety="${STAGING_BACKUP_DIR}/backup_staging_before_restore_$(date +%Y%m%d_%H%M%S).sql.gz"

  log "Ensuring local staging Postgres is up..."
  compose_staging up -d postgres
  local i=0
  until postgres_running staging; do
    i=$((i + 1))
    [[ "$i" -lt 30 ]] || die "Staging Postgres did not become ready."
    sleep 2
  done

  user="$(container_env staging POSTGRES_USER)"
  password="$(container_env staging POSTGRES_PASSWORD)"
  db="$(container_env staging POSTGRES_DB)"
  [[ -n "$user" && -n "$db" && -n "$password" ]] || die "Could not read POSTGRES_* from the staging postgres container."

  log "Stopping staging API to drop DB connections..."
  compose_staging stop api || true

  log "Safety dump of current staging -> $safety"
  safety_dump_docker "$user" "$password" "$db" "$safety" || true

  log "Recreating schema public + pgcrypto on staging Docker Postgres..."
  run_pg18_docker_db "$STAGING_PROJECT" "$user" "$password" "$db" \
    'psql -v ON_ERROR_STOP=1' <<SQL
$(wipe_public_schema_sql)
SQL

  log "Restoring $DUMP_PATH ..."
  restore_stream_to_docker "$user" "$password" "$db"

  log "Invalidating copied refresh / password-reset tokens..."
  run_pg18_docker_db "$STAGING_PROJECT" "$user" "$password" "$db" \
    'psql -v ON_ERROR_STOP=1' <<SQL
$(invalidate_sessions_sql)
SQL

  start_staging_api_docker

  echo
  log "Staging row counts:"
  count_rows_docker || true
}

cmd_restore() {
  require_cmd docker
  [[ -n "$DUMP_PATH" ]] || die "Usage: $0 restore /path/to/backup.sql.gz"
  [[ -f "$DUMP_PATH" ]] || die "Dump not found: $DUMP_PATH"
  [[ -s "$DUMP_PATH" ]] || die "Dump is empty: $DUMP_PATH"
  [[ -f "$(abs_path "$STAGING_COMPOSE_FILE")" ]] || die "Missing $STAGING_COMPOSE_FILE"
  assert_not_production_target
  confirm_overwrite
  ensure_pg18

  cd "$PROJECT_ROOT"

  local rds_url
  rds_url="$(staging_rds_url)"
  if [[ -n "$rds_url" ]]; then
    log "Staging restore target is ApsaraDB ($(redact_url "$rds_url"))."
    restore_to_rds "$rds_url"
  else
    log "Staging restore target is local Docker Postgres ($STAGING_PROJECT)."
    restore_to_docker
  fi

  echo
  warn "Do not run prisma db seed after restore (it would duplicate users/roles)."
  warn "Document files are not in this dump. If staging STORAGE_HOST_PATH is not the same NAS as production, copy files or downloads will 404."
  log "Restore complete. Users must log in again on staging (tokens were cleared)."
}

cmd_verify() {
  ensure_pg18
  cd "$PROJECT_ROOT"
  local rds_url
  rds_url="$(staging_rds_url)"
  if [[ -n "$rds_url" ]]; then
    log "Row counts on staging ApsaraDB:"
    count_rows_rds "$rds_url"
  else
    postgres_running staging || die "Staging Postgres is not running, and no remote DATABASE_URL was found."
    log "Row counts on $STAGING_PROJECT (local Docker):"
    count_rows_docker
  fi
}

usage() {
  cat <<EOF
Dump production PostgreSQL and restore onto staging (Dev backend).

Commands:
  dump                    Take a gzipped SQL dump (run on production)
  restore <file>          Wipe staging and restore <file> (run on staging)
  verify                  Print key table row counts on staging

Dump/restore always use $PG18_IMAGE so the client works for Docker PG 16 and ApsaraDB PG 18.

After staging uses ApsaraDB, restore/verify use STAGING_APSARA_DATABASE_URL
or DATABASE_URL in the staging env file (host must not be postgres).

Examples:
  # Production host
  ./scripts/migrate-prod-to-staging.sh dump

  # Staging host
  CONFIRM=OVERWRITE-STAGING ./scripts/migrate-prod-to-staging.sh \\
    restore /opt/backups/slms-staging/backup_production_20260910_120000.sql.gz

Remote production (ApsaraDB, no local postgres container):
  PROD_DATABASE_URL='postgresql://USER:PASS@HOST:5432/slms?sslmode=require' \\
    ./scripts/migrate-prod-to-staging.sh dump
EOF
}

case "$COMMAND" in
  dump)    cmd_dump ;;
  restore) cmd_restore ;;
  verify)  cmd_verify ;;
  *)       usage; exit 1 ;;
esac
