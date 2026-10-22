ARG PHP_VERSION
FROM php:${PHP_VERSION}-fpm

COPY ./data/supervisor-4.2.5.tar.gz /tmp/
COPY ./data/php-fpm.ini /etc/supervisor.d/php-fpm.ini
COPY ./data/supervisord.conf /etc/supervisord.conf
COPY ./data/install-php-extensions  /usr/local/bin/
COPY ./data/rebuild-php-eol /usr/local/bin/
COPY ./data/prepare-apt /usr/local/bin/
COPY ./data/CVE-2026-109618-109619.patch /usr/local/share/php/backports/7.3.33.patch

# Rebuild only the exact EOL baselines; all other series return immediately.
RUN sh /usr/local/bin/rebuild-php-eol

# PEAR before 1.10.17 cannot decode PECL's chunked HTTP responses.
RUN curl -fsSL --retry 3 https://pear.php.net/get/PEAR-1.10.18.tgz -o /tmp/PEAR.tgz && \
    echo '276db000b4e0a9388c7f5168522174bae4144c8c411a71d480b82ec25ee3bc8b  /tmp/PEAR.tgz' | sha256sum -c - && \
    pear upgrade --offline --loose /tmp/PEAR.tgz && \
    pecl channel-update https://pecl.php.net/channel.xml && \
    rm -rf /tmp/PEAR.tgz /tmp/pear

RUN chmod uga+x /usr/local/bin/prepare-apt && \
    prepare-apt && \
    apt-get update && \
    apt-get install -y python3 python3-pip git wget libzip4 unzip && \
    rm -rf /var/lib/apt/lists/*

RUN cd /tmp && \
    tar -xzvf supervisor-4.2.5.tar.gz && \
    cd supervisor-4.2.5 && \
    python3 setup.py install && \
    mkdir -p /var/log/supervisor /etc/supervisor/conf.d

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
