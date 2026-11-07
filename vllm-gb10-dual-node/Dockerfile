# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8
FROM ${BASE_IMAGE}

ARG IMAGE_VERSION=0.25-optimized-for-ds-v4-flash

USER root

COPY patches/ /opt/dspark-patches/
COPY recipe/vllm/v1/spec_decode/dspark_proposer.py \
    /usr/local/lib/python3.12/dist-packages/vllm/v1/worker/gpu/spec_decode/dspark_proposer.py
COPY LICENSE /usr/share/licenses/vllm-gb10-dual-node/LICENSE

RUN chmod 0755 /opt/dspark-patches/*.sh /opt/dspark-patches/*.py && \
    python3 -m py_compile \
      /usr/local/lib/python3.12/dist-packages/vllm/v1/worker/gpu/spec_decode/dspark_proposer.py \
      /opt/dspark-patches/*.py

LABEL org.opencontainers.image.title="1Panel vLLM GB10 Dual Node" \
      org.opencontainers.image.description="1Panel-maintained DeepSeek V4 Flash DSpark runtime optimized for two NVIDIA GB10 nodes" \
      org.opencontainers.image.source="https://github.com/1Panel-dev/runtime" \
      org.opencontainers.image.url="https://github.com/Anemll/dspark-vllm-gx10" \
      org.opencontainers.image.vendor="1Panel" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.base.name="ghcr.io/anemll/dspark-vllm-gx10:0.1.1" \
      org.opencontainers.image.base.digest="sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8"
