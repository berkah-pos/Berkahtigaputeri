#!/bin/sh
set -eu

if ! printf '%s' "$LOCAL_CENTRAL_RUNTIME_ROLE" | grep -Eq '^[a-z_][a-z0-9_]{0,62}$'; then
  echo "Invalid local central runtime role identifier." >&2
  exit 2
fi

if [ -z "$LOCAL_CENTRAL_RUNTIME_PASSWORD" ]; then
  echo "Local central runtime password must not be empty." >&2
  exit 2
fi

if [ "$LOCAL_CENTRAL_RUNTIME_PASSWORD" = "$PGPASSWORD" ]; then
  echo "Local runtime and bootstrap passwords must be different." >&2
  exit 2
fi

if [ "$LOCAL_CENTRAL_RUNTIME_ROLE" = "$PGUSER" ]; then
  echo "Local runtime role must differ from the PostgreSQL bootstrap account." >&2
  exit 2
fi

exec psql -X --no-psqlrc -v ON_ERROR_STOP=1 \
  --set=bootstrap_role="$PGUSER" \
  --set=central_database="$PGDATABASE" \
  --set=runtime_role="$LOCAL_CENTRAL_RUNTIME_ROLE" \
  --set=runtime_password="$LOCAL_CENTRAL_RUNTIME_PASSWORD" \
  --file=/bootstrap-local.sql
