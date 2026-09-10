#!/bin/sh
set -e
cd /app/apps/api
# Only force the musl engine on Alpine (libc.musl). On Debian (node:20-slim) Prisma must use
# debian-openssl-3.0.x; forcing musl here would cause "libc.musl-x86_64.so.1: cannot open shared object file".
if [ -f /etc/alpine-release ]; then
  PRISMA_ENGINE_PATH=$(find /app -path '*node_modules*' -name 'libquery_engine-linux-musl-openssl-3.0.x.so.node' 2>/dev/null | head -1)
  if [ -n "$PRISMA_ENGINE_PATH" ]; then
    export PRISMA_QUERY_ENGINE_LIBRARY="$PRISMA_ENGINE_PATH"
  fi
fi
echo "Running database migrations..."
attempt=1
# Retries cover local Docker Postgres coming up in parallel (API no longer depends_on postgres)
# and brief ApsaraDB network delays.
max_attempts=45
while [ "$attempt" -le "$max_attempts" ]; do
  if npx prisma migrate deploy; then
    echo "Migrations applied successfully."
    break
  fi
  if [ "$attempt" -eq "$max_attempts" ]; then
    echo "Error: could not run prisma migrate deploy after $max_attempts attempts. Check DATABASE_URL (host ${DB_HOST:-unknown}:${DB_PORT:-5432})."
    exit 1
  fi
  echo "Database not reachable (attempt $attempt/$max_attempts), retrying in 2s..."
  sleep 2
  attempt=$((attempt + 1))
done
exec node dist/main.js
