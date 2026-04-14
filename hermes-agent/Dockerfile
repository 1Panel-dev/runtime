# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=nousresearch/hermes-agent:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/1Panel-dev/runtime" \
  org.opencontainers.image.title="1Panel Hermes Agent" \
  org.opencontainers.image.description="Hermes Agent image maintained by 1Panel with bundled messaging channel dependencies"

USER root

ENV HERMES_RUN_MODE=gateway \
    HERMES_DASHBOARD_HOST=0.0.0.0 \
    HERMES_DASHBOARD_PORT=9119 \
    HERMES_DASHBOARD_NO_OPEN=1 \
    VIRTUAL_ENV=/opt/hermes/.venv \
    PATH=/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY hermes-agent/docker-entrypoint.sh /usr/local/bin/1panel-hermes-entrypoint.sh

RUN chmod 755 /usr/local/bin/1panel-hermes-entrypoint.sh && \
    gosu hermes /usr/local/bin/uv pip install \
      --python /opt/hermes/.venv/bin/python \
      --no-cache-dir \
      aiohttp \
      httpx \
      cryptography \
      dingtalk-stream \
      lark-oapi \
      websockets \
      qrcode

WORKDIR /opt/data/workspace

ENTRYPOINT ["/usr/local/bin/1panel-hermes-entrypoint.sh"]
