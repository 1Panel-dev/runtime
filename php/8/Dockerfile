ARG PHP_VERSION
FROM php:${PHP_VERSION}-fpm

COPY ./data/php-fpm.ini /etc/supervisor.d/php-fpm.ini
COPY ./data/supervisord.conf /etc/supervisord.conf
COPY ./data/install-php-extensions  /usr/local/bin/
COPY ./data/rebuild-php-eol /usr/local/bin/
COPY ./data/prepare-apt /usr/local/bin/
 
# Rebuild only the exact EOL baselines; all other series return immediately.
RUN sh /usr/local/bin/rebuild-php-eol

# Official PHP 8.6 images no longer bundle the PEAR/PECL installer.
RUN if ! command -v pear >/dev/null; then \
        set -e; \
        curl -fsSL --retry 3 https://raw.githubusercontent.com/pear/pearweb_phars/72aa5f771f56aaf826641b21159453f993e44450/install-pear-nozlib.phar -o /tmp/install-pear.phar; \
        echo 'a71349da29f1a6e3f0792695b167e582375a93c70c0e9d35e7c4675697c5f039  /tmp/install-pear.phar' | sha256sum -c -; \
        php -n /tmp/install-pear.phar -d /usr/local/lib/php -b /usr/local/bin; \
        rm /tmp/install-pear.phar; \
    fi

# PEAR before 1.10.17 cannot decode PECL's chunked HTTP responses.
RUN curl -fsSL --retry 3 https://pear.php.net/get/PEAR-1.10.18.tgz -o /tmp/PEAR.tgz && \
    echo '276db000b4e0a9388c7f5168522174bae4144c8c411a71d480b82ec25ee3bc8b  /tmp/PEAR.tgz' | sha256sum -c - && \
    pear upgrade --offline --loose /tmp/PEAR.tgz && \
    pecl channel-update https://pecl.php.net/channel.xml && \
    rm -rf /tmp/PEAR.tgz /tmp/pear

RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor && \
    mkdir -p /var/log/supervisor /etc/supervisor/conf.d && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*  

RUN curl -o /tmp/composer-setup.php https://getcomposer.org/installer \
    && php /tmp/composer-setup.php --install-dir=/tmp \
    && mv /tmp/composer.phar /usr/bin/composer \
    && chmod +x /usr/bin/composer \
    && rm -rf /tmp/composer-setup.php

RUN chmod uga+x /usr/local/bin/install-php-extensions 

ENV COMPOSER_HOME=/tmp/.composer

RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]

WORKDIR /www
