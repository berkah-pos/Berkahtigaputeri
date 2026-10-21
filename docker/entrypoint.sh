#!/usr/bin/env sh
set -eu

mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
# The web image starts a root-owned supervisor, but Coolify queue/migration
# one-shot services should run as www-data (UID 33). Never require root just
# to enter the container or execute an ordinary queue command.
if [ "$(id -u)" -eq 0 ]; then
  chown -R www-data:www-data storage bootstrap/cache
fi

# Keep false for the long-running web service and all ordinary queue workers.
# Run migrations only in an explicitly created one-shot service using the
# database-scoped migration identity, never with bootstrap/provisioner secrets.
if [ "${RUN_CENTRAL_MIGRATIONS:-false}" = "true" ]; then
  php artisan migrate --database=central --path=database/migrations/central --force
fi

# Worker and one-shot services override the command. The public web container
# starts supervisor, which manages Nginx and PHP-FPM.
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/berkah-pos.conf
