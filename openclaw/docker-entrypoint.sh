#!/bin/sh
set -eu

mkdir -p /tmp/caddy /data/caddy /config/caddy

"$@" &
openclaw_pid=$!

/usr/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!

term_handler() {
  kill "$openclaw_pid" "$caddy_pid" 2>/dev/null || true
}

trap term_handler INT TERM HUP

while kill -0 "$openclaw_pid" 2>/dev/null && kill -0 "$caddy_pid" 2>/dev/null; do
  sleep 1
done

term_handler
wait "$openclaw_pid" || true
wait "$caddy_pid" || true
exit 1
