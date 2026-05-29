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

COPY hermes-agent/1panel-banner.sh /etc/cont-init.d/00-1panel-banner
COPY hermes-agent/hermes-gateway-run.sh /usr/local/bin/1panel-hermes-gateway-run
RUN chmod 755 /etc/cont-init.d/00-1panel-banner /usr/local/bin/1panel-hermes-gateway-run

CMD ["1panel-hermes-gateway-run"]
