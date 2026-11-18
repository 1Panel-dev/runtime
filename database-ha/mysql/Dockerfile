ARG MYSQL_VERSION=8.4.13
FROM mysql:${MYSQL_VERSION}

LABEL org.opencontainers.image.source="https://github.com/1Panel-dev/containers" \
      org.opencontainers.image.title="1Panel MySQL Cluster" \
      org.opencontainers.image.description="MySQL replication image with 1Panel application package compatibility" \
      org.opencontainers.image.vendor="1Panel"

USER root

RUN groupmod -g 1001 mysql && \
    usermod -u 1001 -g 1001 mysql && \
    mkdir -p /bitnami/mysql/data /opt/bitnami/mysql/conf /opt/bitnami/mysql/tmp \
      /opt/bitnami/mysql/logs /opt/bitnami/mysql/lib /opt/bitnami/scripts/mysql && \
    ln -s /usr/lib64/mysql/plugin /opt/bitnami/mysql/lib/plugin && \
    chown -R mysql:mysql /bitnami/mysql /opt/bitnami/mysql /var/lib/mysql /var/run/mysqld && \
    command -v mysql && command -v mysqladmin && command -v mysqldump && command -v mysqld

COPY my.cnf /opt/bitnami/mysql/conf/my.cnf
COPY docker-entrypoint.sh /usr/local/bin/1panel-mysql-entrypoint
COPY healthcheck.sh /opt/bitnami/scripts/mysql/healthcheck.sh

RUN chmod 0755 /usr/local/bin/1panel-mysql-entrypoint /opt/bitnami/scripts/mysql/healthcheck.sh && \
    chown mysql:mysql /opt/bitnami/mysql/conf/my.cnf && \
    ln -sf /opt/bitnami/mysql/conf/my.cnf /etc/my.cnf

USER 1001:1001

VOLUME /bitnami/mysql/data

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=6 \
  CMD ["/opt/bitnami/scripts/mysql/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/1panel-mysql-entrypoint"]
CMD ["mysqld"]
