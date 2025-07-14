ARG PHP_VERSION=5.6.40
FROM php:${PHP_VERSION}-fpm

COPY ./data/install-php-extensions  /usr/local/bin/
COPY ./data/composer /usr/bin/composer
COPY ./data/php-fpm.ini /etc/supervisor.d/php-fpm.ini
COPY ./data/supervisord.conf /etc/supervisord.conf

RUN echo "deb http://archive.debian.org/debian/ stretch main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://archive.debian.org/debian-security/ stretch/updates main contrib non-free" >> /etc/apt/sources.list 
    
RUN apt-get -qq update -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true -o APT::Get::AllowUnauthenticated=true && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-install-suggests -o APT::Get::AllowUnauthenticated=true debian-archive-keyring && \
    apt-get update && \
    apt-get install -y supervisor iputils-ping && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    
RUN chmod uga+x /usr/local/bin/install-php-extensions && \
    chmod +x /usr/bin/composer 
    
ENV COMPOSER_HOME=/tmp/.composer

RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]

WORKDIR /www