#!/usr/bin/env sh
set -eu

# Schema changes are release operations, never container-startup side effects.
# Keep this guard so a stale Coolify variable fails closed without running DDL.
if [ "${RUN_CENTRAL_MIGRATIONS:-false}" = "true" ]; then
  echo "ERROR: startup database migrations are disabled; use the reviewed one-shot release task." >&2
  exit 64
fi

mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

# Runtime environment is injected by Coolify. Never bake config cache or secrets into
# the image. Recreate/restart the container after changing environment variables.
if [ "${APP_ENV:-production}" = "production" ]; then
  php artisan config:clear
  su -s /bin/sh -c 'php artisan config:cache' www-data
fi

# Worker services override the command. The public web container starts supervisor.
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/berkah-pos.conf
