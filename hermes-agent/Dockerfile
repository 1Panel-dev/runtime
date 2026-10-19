# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=nousresearch/hermes-agent:v0.22.2
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/1Panel-dev/runtime" \
  org.opencontainers.image.title="1Panel Hermes Agent" \
  org.opencontainers.image.description="Hermes Agent image maintained by 1Panel with bundled messaging channel dependencies"

USER root

ENV HERMES_DASHBOARD=1 \
    HERMES_DASHBOARD_HOST=0.0.0.0 \
    HERMES_DASHBOARD_PORT=9119 \
    VIRTUAL_ENV=/opt/hermes/.venv \
    PATH=/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# PM exposes its internal uv binary through uv_launcher, not installed_package.
RUN uv_bin="$(/usr/local/bin/python3 -c 'from pm import uv_launcher; binary = uv_launcher("uv"); assert binary is not None, "Hermes image has no installed uv launcher"; print(binary)')" && \
    test -x "$uv_bin" && \
    chmod -R u+w /opt/hermes/.venv && \
    "$uv_bin" pip install --no-cache-dir --python "$VIRTUAL_ENV/bin/python" "lark-oapi==1.6.8" "qrcode==7.4.2" && \
    chown -R root:root /opt/hermes/.venv && \
    chmod -R a+rX /opt/hermes/.venv && \
    chmod -R a-w /opt/hermes/.venv

COPY hermes-agent/hermes-gateway-run.sh /usr/local/bin/1panel-hermes-gateway-run
RUN chmod 755 /usr/local/bin/1panel-hermes-gateway-run

CMD ["1panel-hermes-gateway-run"]
