#!/bin/bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

bootstrap_files() {
    mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

    if [ ! -f "$HERMES_HOME/.env" ]; then
        cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
    fi

    if [ ! -f "$HERMES_HOME/config.yaml" ]; then
        cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
    fi

    if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
        cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
    fi

    if [ -d "$INSTALL_DIR/skills" ]; then
        python3 "$INSTALL_DIR/tools/skills_sync.py"
    fi
}

run_dashboard() {
    hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure
}

run_both() {
    local gateway_pid dashboard_pid exit_code

    hermes gateway run &
    gateway_pid=$!

    run_dashboard &
    dashboard_pid=$!

    trap 'kill "$gateway_pid" "$dashboard_pid" 2>/dev/null || true; wait "$gateway_pid" "$dashboard_pid" 2>/dev/null || true' INT TERM

    wait -n "$gateway_pid" "$dashboard_pid"
    exit_code=$?
    kill "$gateway_pid" "$dashboard_pid" 2>/dev/null || true
    wait "$gateway_pid" "$dashboard_pid" 2>/dev/null || true
    return "$exit_code"
}

if [ "$(id -u)" = "0" ]; then
    if [ -n "${HERMES_UID:-}" ] && [ "${HERMES_UID}" != "$(id -u hermes)" ]; then
        echo "Changing hermes UID to ${HERMES_UID}"
        usermod -u "${HERMES_UID}" hermes
    fi

    if [ -n "${HERMES_GID:-}" ] && [ "${HERMES_GID}" != "$(id -g hermes)" ]; then
        echo "Changing hermes GID to ${HERMES_GID}"
        groupmod -g "${HERMES_GID}" hermes
    fi

    actual_hermes_uid="$(id -u hermes)"
    if [ "$(stat -c %u "$HERMES_HOME" 2>/dev/null || echo missing)" != "$actual_hermes_uid" ]; then
        echo "$HERMES_HOME is not owned by $actual_hermes_uid, fixing"
        chown -R hermes:hermes "$HERMES_HOME"
    fi

    exec gosu hermes "$0" "$@"
fi

printf '\033[1;32m%s\033[0m\n' 'This image is maintained by 1Panel.'
printf '\033[1;33m%s\033[0m\n' 'For support or issue discussion, please visit:'
printf '\033[1;36m%s\033[0m\n' 'https://github.com/1Panel-dev/1Panel/discussions'

source "$INSTALL_DIR/.venv/bin/activate"
bootstrap_files
cd "$HERMES_HOME/workspace"

if [ "$#" -gt 0 ]; then
    exec hermes "$@"
fi

case "${HERMES_RUN_MODE:-both}" in
    gateway)
        exec hermes gateway run
        ;;
    dashboard)
        run_dashboard
        ;;
    both)
        run_both
        ;;
    *)
        echo "Unsupported HERMES_RUN_MODE: ${HERMES_RUN_MODE:-both}" >&2
        echo "Supported values: gateway, dashboard, both" >&2
        exit 1
        ;;
esac
