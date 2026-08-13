#!/usr/bin/env bash
set -Eeuo pipefail

is_access_host() {
  node -e '
    const { isIPv4 } = require("node:net");
    const value = process.argv[1];
    const hostname = value.length <= 253 && !/^[0-9.]+$/.test(value) &&
      value.split(".").every((label) => /^(?!-)[A-Za-z0-9-]{1,63}(?<!-)$/.test(label));
    process.exit(isIPv4(value) || hostname ? 0 : 1);
  ' "$1"
}

if [[ "${1:-}" == "--self-test" ]]; then
  is_access_host 203.0.113.10
  is_access_host dsh.example.com
  ! is_access_host https://dsh.example.com
  ! is_access_host 203.0.113.10:10443
  ! is_access_host 203.0.113.999
  exit 0
fi

access_host="${HTTPS_ACCESS_HOST:-}"
auth_username="${DSH_AUTH_USERNAME:-}"
auth_password="${DSH_AUTH_PASSWORD:-}"

if ! is_access_host "$access_host"; then
  printf 'HTTPS_ACCESS_HOST must be an IPv4 address or hostname without a scheme, path, or port.\n' >&2
  exit 1
fi

if [[ ! "$auth_username" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'DSH_AUTH_USERNAME must contain only letters, numbers, dot, underscore, or hyphen.\n' >&2
  exit 1
fi

if (( ${#auth_password} < 12 )); then
  printf 'DSH_AUTH_PASSWORD must contain at least 12 characters.\n' >&2
  exit 1
fi

password_hash="$(caddy hash-password --algorithm argon2id --plaintext "$auth_password")"
unset HTTPS_ACCESS_HOST DSH_AUTH_USERNAME DSH_AUTH_PASSWORD auth_password

install -d -m 0700 -o node -g node /data/dsh /data/dsh/home
install -d -m 0750 -o node -g node /workspace
install -d -m 0700 -o caddy -g caddy /data/caddy /data/caddy/config

pids=()
cleanup() {
  if (( ${#pids[@]} )); then
    kill -TERM "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

gosu node env \
  HOME=/data/dsh/home \
  DSH_HOME=/data/dsh \
  DSH_TELEMETRY_DISABLED=1 \
  dsh web --host 127.0.0.1 --port 3080 --trusted-host 127.0.0.1:3080 &
dsh_pid=$!
pids+=("$dsh_pid")

ready=false
for _ in {1..60}; do
  if curl -fsS --max-time 2 http://127.0.0.1:3080/ >/dev/null 2>&1; then
    ready=true
    break
  fi
  if ! kill -0 "$dsh_pid" 2>/dev/null; then
    wait "$dsh_pid"
    exit $?
  fi
  sleep 1
done

if [[ "$ready" != true ]]; then
  printf 'DeepSeek Harness did not become ready within 60 seconds.\n' >&2
  exit 1
fi

gosu caddy env \
  XDG_DATA_HOME=/data/caddy \
  XDG_CONFIG_HOME=/data/caddy/config \
  CADDY_ACCESS_HOST="$access_host" \
  DSH_AUTH_USERNAME="$auth_username" \
  DSH_AUTH_PASSWORD_HASH="$password_hash" \
  caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!
pids+=("$caddy_pid")

printf 'DeepSeek Harness is available at https://%s:8443 inside the container.\n' "$access_host"
printf 'The local CA certificate is stored at /data/caddy/pki/authorities/local/root.crt.\n'

status=0
wait -n "$dsh_pid" "$caddy_pid" || status=$?
exit "$status"
