# syntax=docker/dockerfile:1

ARG PHP_VERSION=8.4.14
ARG FRANKENPHP_VERSION=v1.9.1
ARG REDIS_VERSION=6.3.0

# ========== 阶段1：编译 PHP ==========
FROM ubuntu:24.04 AS php-build
ENV DEBIAN_FRONTEND=noninteractive \
    PHP_INI_DIR=/usr/local/etc/php \
    MAKEFLAGS="-j$(nproc)"

RUN apt update && apt install -y --no-install-recommends \
    build-essential pkg-config curl ca-certificates git \
    autoconf re2c cmake \
    libxml2-dev libsqlite3-dev libcurl4-openssl-dev libssl-dev libzip-dev \
    libjpeg-dev libpng-dev libwebp-dev libavif-dev libxpm-dev libfreetype-dev \
    libonig-dev libpq-dev libreadline-dev libargon2-dev libicu-dev zlib1g-dev \
    libbz2-dev liblz4-dev libzstd-dev libsodium-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/src && cd /usr/src \
    && curl -fsSL https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz -o php.tar.gz \
    && tar -zxf php.tar.gz && cd php-${PHP_VERSION} \
    && ./configure \
        --prefix=/usr/local \
        --with-config-file-path=${PHP_INI_DIR} \
        --with-config-file-scan-dir=${PHP_INI_DIR}/conf.d \
        --disable-cgi \
        --enable-bcmath \
        --enable-mbstring \
        --enable-gd \
        --with-jpeg \
        --with-webp \
        --with-avif \
        --with-freetype \
        --enable-exif \
        --with-openssl \
        --with-zlib \
        --with-curl \
        --with-zip \
        --with-password-argon2 \
        --with-readline \
        --with-pdo-mysql \
        --with-pdo-pgsql \
        --enable-opcache \
        --enable-mysqlnd \
    && make && make install \
    && mkdir -p ${PHP_INI_DIR}/conf.d \
    && cp php.ini-production ${PHP_INI_DIR}/php.ini \
    && echo "zend_extension=opcache.so" > ${PHP_INI_DIR}/conf.d/opcache.ini

# Redis 扩展
RUN curl -fsSL https://pecl.php.net/get/redis-${REDIS_VERSION}.tgz -o /usr/src/redis.tgz \
    && mkdir -p /usr/src/redis && tar -zxf /usr/src/redis.tgz -C /usr/src/redis --strip-components=1 \
    && cd /usr/src/redis \
    && /usr/local/bin/phpize \
    && ./configure --with-php-config=/usr/local/bin/php-config \
    && make && make install \
    && echo "extension=redis.so" > ${PHP_INI_DIR}/conf.d/redis.ini

# Composer
RUN php -r "copy('https://getcomposer.org/installer','composer-setup.php');" \
    && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
    && php -r "unlink('composer-setup.php');"

# ========== 阶段2：构建 FrankenPHP (Go) ==========
FROM ubuntu:24.04 AS frankenphp-build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y --no-install-recommends \
    curl ca-certificates git build-essential go \
    libssl-dev libreadline-dev libargon2-dev libonig-dev libcurl4-openssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG FRANKENPHP_VERSION
ENV CGO_ENABLED=1
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest \
    && xcaddy build \
       --with github.com/dunglas/frankenphp@${FRANKENPHP_VERSION}

# ========== 阶段3：runtime 基础(common) ==========
FROM ubuntu:24.04 AS common
ENV DEBIAN_FRONTEND=noninteractive \
    PHP_INI_DIR=/usr/local/etc/php

RUN apt update && apt install -y --no-install-recommends \
    ca-certificates curl libargon2-1 libonig5 libreadline8 libssl3 libzip4 \
    libxml2 libsqlite3-0 libcurl4 libjpeg-turbo8 libpng16-16 libwebp7 libavif16 libxpm4 libfreetype6 \
    zlib1g libicu72 liblz4-1 libzstd1 libstdc++6 libbz2-1 libsodium23 libpq5 libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

# 拷贝 PHP 安装
COPY --from=php-build /usr/local /usr/local

WORKDIR /app
RUN mkdir -p /app/public /config/caddy /data/caddy /etc/caddy /etc/frankenphp \
    && echo '<?php echo "OK";' > /app/public/health.php \
    && echo '<?php phpinfo();' > /app/public/index.php

# Caddyfile（支持 /health，HTTP/3 需 TLS 域名时可替换 :443 站点）
COPY --link caddy/frankenphp/Caddyfile /etc/caddy/Caddyfile
RUN ln /etc/caddy/Caddyfile /etc/frankenphp/Caddyfile || true

# 安装扩展脚本（备用）
RUN curl -fsSL -o /usr/local/bin/install-php-extensions \
      https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    && chmod +x /usr/local/bin/install-php-extensions

ENV XDG_CONFIG_HOME=/config \
    XDG_DATA_HOME=/data

EXPOSE 80 443 443/udp 2019

# ========== 阶段4：runner (拷贝 FrankenPHP/Caddy 二进制) ==========
FROM common AS runner
ARG FRANKENPHP_VERSION
ENV FRANKENPHP_VERSION=${FRANKENPHP_VERSION} GODEBUG=cgocheck=0

# 拷贝带 FrankenPHP 模块的 caddy
COPY --from=frankenphp-build /usr/local/bin/caddy /usr/local/bin/frankenphp

# 低端口权限
RUN setcap cap_net_bind_service=+ep /usr/local/bin/frankenphp

# 健康检查 (Caddy admin /metrics)
HEALTHCHECK CMD curl -fsS http://localhost:2019/metrics || exit 1

# 运行用户
RUN useradd -r -u 1000 -g users -d /app -s /usr/sbin/nologin app || true \
    && chown -R app:users /app
USER app

ENTRYPOINT ["/usr/local/bin/frankenphp"]
CMD ["run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]