FROM caddy:2.11.4 AS caddy

FROM node:24-bookworm-slim

ARG DSH_VERSION=0.1.0-rc.6

LABEL org.opencontainers.image.title="DeepSeek Harness" \
      org.opencontainers.image.source="https://github.com/deepseek-ai/deepseek-harness"

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      bubblewrap \
      ca-certificates \
      curl \
      git \
      gosu \
      openssh-client \
      ripgrep \
      tini && \
    rm -rf /var/lib/apt/lists/*

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy

RUN groupadd --system --gid 1001 caddy && \
    useradd --system --uid 1001 --gid caddy --home-dir /var/lib/caddy \
      --create-home --shell /usr/sbin/nologin caddy && \
    npm install --global "@deepseek-ai/dsh@${DSH_VERSION}" && \
    npm cache clean --force && \
    install -d -m 0700 -o node -g node /data/dsh /data/dsh/home && \
    install -d -m 0750 -o node -g node /workspace && \
    install -d -m 0700 -o caddy -g caddy /data/caddy /data/caddy/config

COPY deepseek-harness/Caddyfile /etc/caddy/Caddyfile
COPY deepseek-harness/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh && \
    /usr/local/bin/docker-entrypoint.sh --self-test

ENV DSH_HOME=/data/dsh \
    DSH_TELEMETRY_DISABLED=1

WORKDIR /workspace

EXPOSE 8443

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS --max-time 5 http://127.0.0.1:3080/ >/dev/null || exit 1

STOPSIGNAL SIGTERM

ENTRYPOINT ["tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
