ARG PHP_VERSION=5.6.40
FROM php:${PHP_VERSION}-fpm

COPY ./data/install-php-extensions  /usr/local/bin/
COPY ./data/composer /usr/bin/composer
COPY ./data/php-fpm.ini /etc/supervisor.d/php-fpm.ini
COPY ./data/supervisord.conf /etc/supervisord.conf
COPY ./data/rebuild-php-eol ./data/prepare-apt /usr/local/bin/
COPY ./data/CVE-2026-109618-109619.patch /usr/local/share/php/backports/5.6.40.patch

# Bootstrap current archive signing keys over HTTPS before using signed Stretch metadata.
RUN curl -fsSL --retry 3 https://archive.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2021.1.1+deb11u1_all.deb -o /tmp/archive-keyring.deb && \
    echo '28ca7749ab7978f3c571732c3aa1c56e3ad1d5db3c915293763d4f6cb8fcce89  /tmp/archive-keyring.deb' | sha256sum -c - && \
    dpkg -i /tmp/archive-keyring.deb && rm /tmp/archive-keyring.deb

RUN sh /usr/local/bin/rebuild-php-eol

RUN apt-get update && \
    apt-get install -y supervisor iputils-ping && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# PEAR before 1.10.17 cannot decode PECL's chunked HTTP responses.
RUN curl -fsSL --retry 3 https://pear.php.net/get/Archive_Tar-1.4.14.tgz -o /tmp/Archive_Tar.tgz && \
    echo '4af263e4fdfcb400f888f84cccf8d05d1be2eb78128349431405b2ffb0c0c9f4  /tmp/Archive_Tar.tgz' | sha256sum -c - && \
    pear upgrade --offline --loose /tmp/Archive_Tar.tgz && \
    curl -fsSL --retry 3 https://pear.php.net/get/PEAR-1.10.18.tgz -o /tmp/PEAR.tgz && \
    echo '276db000b4e0a9388c7f5168522174bae4144c8c411a71d480b82ec25ee3bc8b  /tmp/PEAR.tgz' | sha256sum -c - && \
    pear upgrade --offline --loose /tmp/PEAR.tgz && \
    pecl channel-update https://pecl.php.net/channel.xml && \
    rm -rf /tmp/Archive_Tar.tgz /tmp/PEAR.tgz /tmp/pear

RUN chmod uga+x /usr/local/bin/install-php-extensions && \
    chmod +x /usr/bin/composer 
    
ENV COMPOSER_HOME=/tmp/.composer

RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]

WORKDIR /www
