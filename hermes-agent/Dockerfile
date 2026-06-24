# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=nousresearch/hermes-agent:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/1Panel-dev/runtime" \
  org.opencontainers.image.title="1Panel Hermes Agent" \
  org.opencontainers.image.description="Hermes Agent image maintained by 1Panel with bundled messaging channel dependencies"

USER root

ENV HERMES_DASHBOARD=1 \
    HERMES_DASHBOARD_HOST=0.0.0.0 \
    HERMES_DASHBOARD_PORT=9119 \
    VIRTUAL_ENV=/opt/hermes/.venv \
    PATH=/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN chmod -R u+w /opt/hermes/.venv && \
    hermes_version="$(python -c 'import importlib.metadata as m; print(m.version("hermes-agent"))')" && \
    python -m pip install --no-cache-dir "hermes-agent[feishu]==${hermes_version}" && \
    chown -R root:root /opt/hermes/.venv && \
    chmod -R a+rX /opt/hermes/.venv && \
    chmod -R a-w /opt/hermes/.venv

COPY hermes-agent/hermes-gateway-run.sh /usr/local/bin/1panel-hermes-gateway-run
RUN chmod 755 /usr/local/bin/1panel-hermes-gateway-run

CMD ["1panel-hermes-gateway-run"]
