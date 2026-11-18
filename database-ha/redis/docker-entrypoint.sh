#!/bin/bash
set -euo pipefail

if [[ "${1:-}" != "redis-server" ]]; then
    exec "$@"
fi
shift

log() {
    local level="$1"
    shift
    printf '%s [%s] Redis cluster (%s): %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "${role:-startup}" "$*" >&2
}

fail() {
    log ERROR "$*"
    exit 1
}

role="${REDIS_REPLICATION_MODE:-master}"
log INFO 'Validating replication settings'
case "$role" in
    master) ;;
    slave)
        [[ -n "${REDIS_MASTER_HOST:-}" ]] || fail 'REDIS_MASTER_HOST is required for a slave'
        [[ -n "${REDIS_MASTER_PASSWORD:-}" ]] || fail 'REDIS_MASTER_PASSWORD is required for a slave'
        master_port="${REDIS_MASTER_PORT_NUMBER:-6379}"
        if [[ ! "$master_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$master_port < 1 || 10#$master_port > 65535 )); then
            fail 'REDIS_MASTER_PORT_NUMBER must be between 1 and 65535'
        fi
        ;;
    *)
        fail 'REDIS_REPLICATION_MODE must be master or slave'
        ;;
esac
[[ -n "${REDIS_PASSWORD:-}" ]] || fail 'REDIS_PASSWORD is required'

umask 0077
config=/opt/bitnami/redis/etc/redis.conf
log INFO 'Preparing data and configuration directories'
mkdir -p /bitnami/redis/data /opt/bitnami/redis/etc /opt/bitnami/redis/logs
args=("$config")

if [[ -f /opt/bitnami/redis/mounted-etc/redis.conf ]]; then
    log INFO 'Using mounted Redis configuration; replication and persistence settings are preserved'
    cp /opt/bitnami/redis/mounted-etc/redis.conf "$config"
else
    log INFO 'Generating default Redis configuration with AOF enabled'
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
        log INFO 'Applying replica connection settings'
        args+=(--masterauth "$REDIS_MASTER_PASSWORD" --replicaof "$REDIS_MASTER_HOST" "$master_port")
    else
        log INFO 'Applying primary authentication settings'
        args+=(--masterauth "$REDIS_PASSWORD")
    fi
fi

args+=(--daemonize no)
if [[ -n "${REDIS_EXTRA_FLAGS:-}" || "$#" != 0 ]]; then
    log INFO 'Applying additional Redis arguments'
fi
if [[ "${REDIS_EXTRA_FLAGS:-}" == "--requirepass $REDIS_PASSWORD" ]]; then
    args+=(--requirepass "$REDIS_PASSWORD")
elif [[ -n "${REDIS_EXTRA_FLAGS:-}" ]]; then
    read -r -a extra_flags <<< "$REDIS_EXTRA_FLAGS"
    args+=("${extra_flags[@]}")
fi

log INFO 'Starting Redis server'
exec redis-server "${args[@]}" "$@"
