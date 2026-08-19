#!/bin/bash
set -Eeuo pipefail

readonly COMFYUI_ROOT=/opt/ComfyUI
readonly COMFYUI_DATA=/data
readonly -a COMFYUI_DATA_DIRS=(
  "${COMFYUI_DATA}"
  "${COMFYUI_DATA}/cache"
  "${COMFYUI_DATA}/cache/cuda"
  "${COMFYUI_DATA}/cache/huggingface"
  "${COMFYUI_DATA}/cache/torch"
  "${COMFYUI_DATA}/cache/torchinductor"
  "${COMFYUI_DATA}/cache/triton"
  "${COMFYUI_DATA}/config"
  "${COMFYUI_DATA}/custom_nodes"
  "${COMFYUI_DATA}/home"
  "${COMFYUI_DATA}/input"
  "${COMFYUI_DATA}/models"
  "${COMFYUI_DATA}/output"
  "${COMFYUI_DATA}/python"
  "${COMFYUI_DATA}/temp"
  "${COMFYUI_DATA}/user"
)

if [[ "${1:-}" == "--self-test" ]]; then
  test -f "${COMFYUI_ROOT}/main.py"
  test -f "${COMFYUI_ROOT}/pyproject.toml"
  test -d "${COMFYUI_DATA}/models"
  test -d "${COMFYUI_DATA}/user"
  /usr/bin/id comfyui >/dev/null
  write_test="${COMFYUI_DATA}/.entrypoint-write-test"
  /usr/sbin/gosu comfyui /usr/bin/touch "${write_test}"
  /usr/bin/rm -f "${write_test}"
  exit 0
fi

if [[ "$#" -eq 0 || "${1:-}" == "comfyui" ]]; then
  if [[ "$#" -gt 0 ]]; then
    shift
  fi
  set -- /usr/local/bin/python "${COMFYUI_ROOT}/main.py" \
    --listen "${COMFYUI_LISTEN:-0.0.0.0}" \
    --port "${COMFYUI_PORT:-8188}" \
    --base-directory "${COMFYUI_DATA}" \
    --database-url "${COMFYUI_DATABASE_URL:-sqlite:////data/user/comfyui.db}" \
    "$@"
elif [[ "${1:0:1}" == "-" ]]; then
  set -- /usr/local/bin/python "${COMFYUI_ROOT}/main.py" \
    --listen "${COMFYUI_LISTEN:-0.0.0.0}" \
    --port "${COMFYUI_PORT:-8188}" \
    --base-directory "${COMFYUI_DATA}" \
    --database-url "${COMFYUI_DATABASE_URL:-sqlite:////data/user/comfyui.db}" \
    "$@"
fi

if (( EUID == 0 )); then
  for data_dir in "${COMFYUI_DATA_DIRS[@]}"; do
    if [[ -L "${data_dir}" ]]; then
      printf 'Refusing to initialize symlinked data directory: %s\n' "${data_dir}" >&2
      exit 1
    fi
  done

  /usr/bin/install -d -m 0755 -o comfyui -g comfyui "${COMFYUI_DATA_DIRS[@]}"
  exec /usr/sbin/gosu comfyui "$@"
fi

exec "$@"
