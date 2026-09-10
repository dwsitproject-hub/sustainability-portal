#!/usr/bin/env sh
# Run PRODUCTION backend stack with the correct env file loaded.
# Compose file: docker-compose.prod.backend.yml (project name: slms-prod-backend).
# Development backend: ./infra/up-dev-backend.sh (docker-compose.dev.backend.yml).
#
# Usage (from repo root):
#   ./infra/up-prod-backend.sh up -d --build        # first start (includes local Postgres)
#   ./infra/up-prod-backend.sh up -d --build api    # routine API rebuild (does not start Postgres)
#   ./infra/up-prod-backend.sh up -d redis api      # after ApsaraDB cutover
#   ./infra/up-prod-backend.sh down
# See docs/MIGRATE-TO-APSARA-DB.md
#
# Routine deploy: use up -d --build (Docker reuses cached layers when possible).
# Use build --no-cache only when troubleshooting stale cache or dependency issues.
# If builds fail with "No space left on device", run ./infra/clean-dev-cache.sh on the server first.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/env.prod.backend"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.prod.backend.yml"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: env file not found: $ENV_FILE"
  echo "Copy env.example.backend to env.prod.backend and set your variables."
  exit 1
fi

cd "$PROJECT_ROOT"
exec docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
