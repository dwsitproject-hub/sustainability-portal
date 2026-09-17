#!/usr/bin/env sh
# Run DEVELOPMENT backend stack (Postgres, Redis, API) with the correct env file.
# Compose file: docker-compose.dev.backend.yml (project name: slms-dev-backend).
# Production backend: ./infra/up-prod-backend.sh (docker-compose.prod.backend.yml).
#
# Usage (from repo root or infra/):
#   ./infra/up-dev-backend.sh up -d                 # first start (includes local Postgres)
#   ./infra/up-dev-backend.sh up -d --build api     # routine API rebuild (does not start Postgres)
#   ./infra/up-dev-backend.sh up -d redis api       # after ApsaraDB cutover
#   ./infra/up-dev-backend.sh down
# See docs/MIGRATE-TO-APSARA-DB.md
#
# Routine deploy: use up -d --build api (Docker reuses cached layers when possible).
# Use build --no-cache only when troubleshooting stale cache or dependency issues.
# If the server is low on space, run ./infra/clean-dev-cache.sh first.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Prefer .env.be.dev, fall back to .env for dev backend
ENV_FILE="${SCRIPT_DIR}/.env.be.dev"
[ -f "$ENV_FILE" ] || ENV_FILE="${SCRIPT_DIR}/.env"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.dev.backend.yml"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: env file not found. Create infra/.env or infra/.env.be.dev (e.g. copy from env.example)."
  exit 1
fi

cd "$PROJECT_ROOT"
exec docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
