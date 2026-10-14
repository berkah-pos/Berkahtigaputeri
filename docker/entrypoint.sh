#!/usr/bin/env sh
set -eu

mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

if [ "${RUN_CENTRAL_MIGRATIONS:-false}" = "true" ]; then
  php artisan migrate --database=central --path=database/migrations/central --force
fi

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/berkah-pos.conf
