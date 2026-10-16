FROM composer:2.9.8@sha256:b09bccd91a78fe8a9ab4b33d707b862e8fe54fec17782e32683ad2a69c46867d AS composer-bin

FROM php:8.4.25-fpm-bookworm@sha256:0a5638c2c48eb04987107ae448a398dd18345bcf659e15fd99a422617e754264 AS php-base
ENV DEBIAN_FRONTEND=noninteractive \
    COMPOSER_ALLOW_SUPERUSER=1
WORKDIR /var/www/berkah-pos

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx supervisor curl git unzip libicu-dev libzip-dev libpq-dev \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql pdo_pgsql bcmath intl gd zip opcache \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer-bin /usr/bin/composer /usr/local/bin/composer

FROM php-base AS production
ARG VCS_REF=unknown
LABEL org.opencontainers.image.source="https://github.com/berkah-pos/Berkahtigaputeri" \
      org.opencontainers.image.revision="${VCS_REF}"

# Both CI and production require this exact manifest/lock pair.
COPY composer.json composer.lock ./
RUN set -eux; \
    composer validate --strict --no-check-publish; \
    composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts --optimize-autoloader

COPY . /var/www/berkah-pos
RUN set -eux; \
    mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache; \
    chown -R www-data:www-data storage bootstrap/cache; \
    composer dump-autoload --no-dev --no-interaction --optimize; \
    composer audit --locked --no-dev --no-interaction; \
    chown -R www-data:www-data storage bootstrap/cache; \
    chmod +x docker/entrypoint.sh

COPY docker/nginx.conf /etc/nginx/sites-available/default
COPY docker/supervisord.conf /etc/supervisor/conf.d/berkah-pos.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 CMD curl -fsS http://127.0.0.1/up || exit 1
ENTRYPOINT ["docker/entrypoint.sh"]
