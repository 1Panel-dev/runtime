#!/bin/sh
set -eu

PLAYWRIGHT_ROOT="${PLAYWRIGHT_BROWSERS_PATH:-/home/node/.cache/ms-playwright}"
STABLE_BROWSER_LINK="${PLAYWRIGHT_ROOT}/openclaw-browser"
LATEST_BROWSER_PATH="$(
    find "$PLAYWRIGHT_ROOT" -type f \( -path '*/chrome-linux64/chrome' -o -path '*/chrome-linux/chrome' \) 2>/dev/null \
        | sort -V \
        | tail -n 1
)"

if [ -n "${LATEST_BROWSER_PATH}" ]; then
    mkdir -p "$PLAYWRIGHT_ROOT"
    ln -sfn "$LATEST_BROWSER_PATH" "$STABLE_BROWSER_LINK"
fi

printf '\033[1;32m%s\033[0m\n' 'This image is maintained by 1Panel.'
printf '\033[1;33m%s\033[0m\n' 'For support or issue discussion, please visit:'
printf '\033[1;36m%s\033[0m\n' 'https://github.com/1Panel-dev/1Panel/discussions'

exec "$@"
