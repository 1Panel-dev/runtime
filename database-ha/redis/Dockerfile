ARG REDIS_VERSION=7.4.12
ARG REDIS_VARIANT=bookworm
FROM redis:${REDIS_VERSION}-${REDIS_VARIANT}

LABEL org.opencontainers.image.source="https://github.com/1Panel-dev/runtime" \
      org.opencontainers.image.title="1Panel Redis Replication" \
      org.opencontainers.image.description="Redis replication image with compatibility for 1Panel application packages" \
      org.opencontainers.image.vendor="1Panel"

USER root

RUN groupmod --gid 1001 redis && \
    usermod --uid 1001 --gid 1001 redis && \
    mkdir -p /bitnami/redis/data /opt/bitnami/redis/etc \
      /opt/bitnami/redis/mounted-etc /opt/bitnami/redis/logs && \
    chown -R 1001:1001 /bitnami/redis /opt/bitnami/redis /data

COPY docker-entrypoint.sh /usr/local/bin/1panel-redis-entrypoint
RUN chmod 0755 /usr/local/bin/1panel-redis-entrypoint

USER 1001:1001
WORKDIR /bitnami/redis/data

EXPOSE 6379
STOPSIGNAL SIGTERM
ENTRYPOINT ["1panel-redis-entrypoint"]
CMD ["redis-server"]
