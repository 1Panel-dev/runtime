#!/bin/bash
set -euo pipefail

if [[ "${1:-}" != "redis-server" ]]; then
    exec "$@"
fi
shift

role="${REDIS_REPLICATION_MODE:-master}"
case "$role" in
    master) ;;
    slave)
        : "${REDIS_MASTER_HOST:?REDIS_MASTER_HOST is required for a slave}"
        : "${REDIS_MASTER_PASSWORD:?REDIS_MASTER_PASSWORD is required for a slave}"
        master_port="${REDIS_MASTER_PORT_NUMBER:-6379}"
        if [[ ! "$master_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$master_port < 1 || 10#$master_port > 65535 )); then
            printf '%s\n' 'REDIS_MASTER_PORT_NUMBER must be between 1 and 65535' >&2
            exit 1
        fi
        ;;
    *)
        printf '%s\n' 'REDIS_REPLICATION_MODE must be master or slave' >&2
        exit 1
        ;;
esac
: "${REDIS_PASSWORD:?REDIS_PASSWORD is required}"

umask 0077
config=/opt/bitnami/redis/etc/redis.conf
mkdir -p /bitnami/redis/data /opt/bitnami/redis/etc /opt/bitnami/redis/logs
args=("$config")

if [[ -f /opt/bitnami/redis/mounted-etc/redis.conf ]]; then
    cp /opt/bitnami/redis/mounted-etc/redis.conf "$config"
else
    cat > "$config" <<'EOF'
bind 0.0.0.0
port 6379
protected-mode yes
daemonize no
logfile ""
dir /bitnami/redis/data
appendonly yes
appendfsync everysec
save ""
EOF
    args+=(--requirepass "$REDIS_PASSWORD")
    if [[ "$role" == slave ]]; then
        args+=(--masterauth "$REDIS_MASTER_PASSWORD" --replicaof "$REDIS_MASTER_HOST" "$master_port")
    else
        args+=(--masterauth "$REDIS_PASSWORD")
    fi
fi

args+=(--daemonize no)
if [[ "${REDIS_EXTRA_FLAGS:-}" == "--requirepass $REDIS_PASSWORD" ]]; then
    args+=(--requirepass "$REDIS_PASSWORD")
elif [[ -n "${REDIS_EXTRA_FLAGS:-}" ]]; then
    read -r -a extra_flags <<< "$REDIS_EXTRA_FLAGS"
    args+=("${extra_flags[@]}")
fi

exec redis-server "${args[@]}" "$@"
