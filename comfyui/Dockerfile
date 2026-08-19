# syntax=docker/dockerfile:1.7

ARG PYTHON_IMAGE=docker.io/library/python:3.13.14-slim-bookworm@sha256:67a1e1f215ccda113cfc024e8639049257e88f273898f595b61476d128d387e8
FROM ${PYTHON_IMAGE}

ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu130
ARG TORCH_VERSION=2.13.0+cu130
ARG TORCHVISION_VERSION=0.28.0+cu130
ARG TORCHAUDIO_VERSION=2.11.0+cu130
ARG TARGETARCH

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    HOME=/data/home \
    XDG_CACHE_HOME=/data/cache \
    XDG_CONFIG_HOME=/data/config \
    HF_HOME=/data/cache/huggingface \
    TORCH_HOME=/data/cache/torch \
    TORCHINDUCTOR_CACHE_DIR=/data/cache/torchinductor \
    TRITON_CACHE_DIR=/data/cache/triton \
    CUDA_CACHE_PATH=/data/cache/cuda \
    PYTHONUSERBASE=/data/python \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:/data/python/bin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN case "${TARGETARCH}" in \
      amd64|arm64) ;; \
      *) echo "Unsupported target architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      ffmpeg \
      git \
      gosu \
      libgl1 \
      libglib2.0-0 \
      libgomp1 \
      tini && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 comfyui && \
    useradd --uid 10001 --gid comfyui --create-home --shell /bin/bash comfyui && \
    install -d -m 0755 -o comfyui -g comfyui \
      /data \
      /data/cache \
      /data/cache/cuda \
      /data/cache/huggingface \
      /data/cache/torch \
      /data/cache/torchinductor \
      /data/cache/triton \
      /data/config \
      /data/custom_nodes \
      /data/home \
      /data/input \
      /data/models \
      /data/output \
      /data/python \
      /data/temp \
      /data/user \
      /opt/ComfyUI

WORKDIR /opt/ComfyUI

RUN python -m pip install --no-cache-dir \
      --extra-index-url "${PYTORCH_INDEX_URL}" \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}" \
      "torchaudio==${TORCHAUDIO_VERSION}" && \
    test "$(python -c 'import torch; print(torch.__version__)')" = "${TORCH_VERSION}" && \
    test "$(python -c 'import torchvision; print(torchvision.__version__)')" = "${TORCHVISION_VERSION}" && \
    test "$(python -c 'import torchaudio; print(torchaudio.__version__)')" = "${TORCHAUDIO_VERSION}"

ARG COMFYUI_VERSION=0.33.1
ARG COMFYUI_REVISION=72865f4f27eaf5396f8f36370e0a2be3a9a090ee

RUN set -eux; \
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
      "https://github.com/Comfy-Org/ComfyUI/archive/${COMFYUI_REVISION}.tar.gz" \
      | tar -xz -C /opt/ComfyUI --strip-components=1; \
    actual_version="$(python -c 'import tomllib; print(tomllib.load(open("pyproject.toml", "rb"))["project"]["version"])')"; \
    test "${actual_version}" = "${COMFYUI_VERSION}"

RUN python -m pip install --no-cache-dir \
      --requirement requirements.txt \
      --requirement manager_requirements.txt && \
    pip_check="$(python -m pip check 2>&1 || true)" && \
    unexpected_pip_check="$( \
      printf '%s\n' "${pip_check}" \
        | grep -vF 'nvidia-cusparselt-cu13 0.8.1 is not supported on this platform' \
        | grep -vF 'No broken requirements found.' \
        | grep -v '^$' \
        || true \
    )" && \
    if [ -n "${unexpected_pip_check}" ]; then \
      printf '%s\n' "${unexpected_pip_check}" >&2; \
      exit 1; \
    fi && \
    /usr/sbin/gosu comfyui /usr/local/bin/python /opt/ComfyUI/main.py \
      --quick-test-for-ci \
      --cpu \
      --disable-all-custom-nodes \
      --database-url sqlite:///:memory: \
      --base-directory /tmp/comfyui-quick-test && \
    rm -rf /tmp/comfyui-quick-test

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,video \
    CUDA_MODULE_LOADING=LAZY

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh && \
    /usr/local/bin/docker-entrypoint.sh --self-test

LABEL org.opencontainers.image.title="ComfyUI" \
      org.opencontainers.image.description="ComfyUI NVIDIA CUDA runtime image maintained by 1Panel" \
      org.opencontainers.image.source="https://github.com/Comfy-Org/ComfyUI" \
      org.opencontainers.image.url="https://www.comfy.org/" \
      org.opencontainers.image.documentation="https://docs.comfy.org/" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.vendor="1Panel" \
      org.opencontainers.image.version="v${COMFYUI_VERSION}" \
      org.opencontainers.image.revision="${COMFYUI_REVISION}" \
      org.opencontainers.image.base.name="docker.io/library/python:3.13.14-slim-bookworm" \
      org.opencontainers.image.base.digest="sha256:67a1e1f215ccda113cfc024e8639049257e88f273898f595b61476d128d387e8"

EXPOSE 8188

VOLUME ["/data"]

HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=12 \
  CMD /usr/bin/curl --disable -fsS --max-time 5 "http://127.0.0.1:${COMFYUI_PORT:-8188}/system_stats" >/dev/null || exit 1

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["comfyui"]
