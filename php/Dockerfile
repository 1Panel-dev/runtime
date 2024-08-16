ARG PHP_VERSION
FROM php:${PHP_VERSION}-fpm

RUN apt-get update && apt-get install -y supervisor && \
    mkdir -p /var/log/supervisor

ADD ./data/install-php-extensions  /usr/local/bin/
RUN chmod uga+x /usr/local/bin/install-php-extensions

COPY ./data/php-fpm.ini /etc/supervisor.d/php-fpm.ini
COPY ./data/supervisord.conf /etc/supervisord.conf

RUN curl -o /usr/bin/composer https://mirrors.aliyun.com/composer/composer.phar \
    && chmod +x /usr/bin/composer
ENV COMPOSER_HOME=/tmp/composer

RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]

WORKDIR /www