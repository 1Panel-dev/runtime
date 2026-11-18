ARG POSTGRESQL_VERSION=18.7
FROM postgres:${POSTGRESQL_VERSION}-bookworm

LABEL org.opencontainers.image.source="https://github.com/1Panel-dev/containers" \
      org.opencontainers.image.title="1Panel PostgreSQL replication" \
      org.opencontainers.image.description="PostgreSQL streaming replication with 1Panel cluster environment variables"

RUN groupmod -g 1001 postgres && \
    usermod -u 1001 -g 1001 postgres && \
    mkdir -p /bitnami/postgresql/conf && \
    chown -R postgres:postgres /bitnami /var/lib/postgresql /var/run/postgresql

ENV PGDATA=/bitnami/postgresql/data

COPY entrypoint.sh /usr/local/bin/1panel-postgresql-entrypoint
COPY healthcheck.sh /usr/local/bin/1panel-postgresql-healthcheck
RUN chmod 755 /usr/local/bin/1panel-postgresql-entrypoint /usr/local/bin/1panel-postgresql-healthcheck

USER 1001:1001
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 CMD ["1panel-postgresql-healthcheck"]
ENTRYPOINT ["1panel-postgresql-entrypoint"]
CMD ["postgres"]
