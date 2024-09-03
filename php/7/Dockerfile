ARG PHP_VERSION
FROM php:${PHP_VERSION}-fpm

COPY ./data/supervisor-4.2.5.tar.gz /tmp/
COPY ./data/php-fpm.ini /etc/supervisor.d/php-fpm.ini
COPY ./data/supervisord.conf /etc/supervisord.conf
COPY ./data/install-php-extensions  /usr/local/bin/
COPY ./data/composer /usr/bin/composer


ENV PHP_INI_DIR /usr/local/etc/php
ENV PHP_EXTENSION_DIR /php/extensions
 
RUN apt-get update && \
    apt-get install -y python3 python3-pip git && \
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

ENV COMPOSER_HOME=/usr/bin/composer

RUN mkdir -p $PHP_EXTENSION_DIR

RUN echo "extension_dir=$PHP_EXTENSION_DIR" > $PHP_INI_DIR/conf.d/00-custom-ext-dir.ini


RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]

WORKDIR /www