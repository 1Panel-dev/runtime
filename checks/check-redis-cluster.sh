#!/bin/bash
set -euo pipefail

IMAGE="${1:-${IMAGE:-}}"
: "${IMAGE:?Pass the Redis replication image as the first argument or set IMAGE}"
prefix="1panel-redis-check-$(date +%s)-$$"
master="$prefix-master"
replica="$prefix-slave"
master_data="$prefix-master-data"
replica_data="$prefix-slave-data"
master_conf="$prefix-conf"
master_password=$'master space "quote" \\backslash $dollar `literal`'
replica_password=$'slave space "quote" \\backslash $different `literal`'
volumes=()
containers=()
network_created=false

cleanup() {
    if (( ${#containers[@]} )); then
        docker rm -fv "${containers[@]}" >/dev/null 2>&1 || true
    fi
    if (( ${#volumes[@]} )); then
        docker volume rm "${volumes[@]}" >/dev/null 2>&1 || true
    fi
    if [[ "$network_created" == true ]]; then
        docker network rm "$prefix" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

redis_version=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | sed -n 's/^REDIS_VERSION=//p')
case "$redis_version" in
    6.2.*) aof_file=/bitnami/redis/data/appendonly.aof ;;
    7.4.*|8.10.*) aof_file=/bitnami/redis/data/appendonlydir/appendonly.aof.manifest ;;
    *)
        printf 'Unsupported Redis test version: %s\n' "$redis_version" >&2
        exit 1
        ;;
esac

master_cli() {
    docker exec -e REDISCLI_AUTH="$master_password" "$master" redis-cli --raw -p 6380 "$@"
}

replica_cli() {
    docker exec -e REDISCLI_AUTH="$replica_password" "$replica" redis-cli --raw -p 6381 "$@"
}

wait_for() {
    local expected="$1"
    shift
    local result attempt
    for (( attempt=0; attempt<60; attempt++ )); do
        if result=$("$@" 2>/dev/null) && [[ "$result" == "$expected" ]]; then
            return 0
        fi
        sleep 1
    done
    printf 'Timed out waiting for %s\n' "$expected" >&2
    docker logs "$master" >&2 || true
    docker logs "$replica" >&2 || true
    return 1
}

check_logs() {
    local container="$1" role="$2"
    shift 2
    local started_at logs message password missing
    started_at="$(docker inspect --format '{{.State.StartedAt}}' "$container")"
    local deadline=$((SECONDS + 60))
    while (( SECONDS < deadline )); do
        logs="$(docker logs --since "$started_at" "$container" 2>&1)"
        for password in "$master_password" "$replica_password" config-password; do
            if grep -Fq -- "$password" <<< "$logs"; then
                printf 'Configured password found in container output: %s\n' "$container" >&2
                return 1
            fi
        done
        missing=''
        for message in 'Validating replication settings' 'Preparing data and configuration directories' 'Starting Redis server' "$@"; do
            if ! grep -Fq -- "[INFO] Redis cluster ($role): $message" <<< "$logs"; then
                missing="$message"
                break
            fi
        done
        if [[ -z "$missing" && "$logs" != *'Ready to accept connections'* ]]; then
            missing='Redis engine accepting connections'
        fi
        [[ -n "$missing" ]] || return 0
        sleep 1
    done
    printf 'Log check timed out after 60s: %s, waiting for %s\n' "$container" "$missing" >&2
    return 1
}

containers+=("$prefix-invalid" "$prefix-init")
if docker run --rm --name "$prefix-invalid" -e REDIS_PASSWORD=unused -e REDIS_REPLICATION_MODE=sentinel "$IMAGE" >/dev/null 2>&1; then
    printf '%s\n' 'Unsupported replication mode was accepted' >&2
    exit 1
fi

docker network create "$prefix" >/dev/null
network_created=true
for volume in "$master_data" "$replica_data" "$master_conf"; do
    docker volume create "$volume" >/dev/null
    volumes+=("$volume")
done

docker run --rm --name "$prefix-init" --user 0:0 --entrypoint sh -v "$master_conf:/config" "$IMAGE" -c '
    printf "%s\n" "bind 0.0.0.0" "protected-mode yes" "port 6380" "dir /bitnami/redis/data" "appendonly no" "save \"\"" "maxmemory 64mb" "requirepass config-password" > /config/redis.conf
    chown 1001:1001 /config/redis.conf
' >/dev/null

docker create --name "$master" --network "$prefix" \
    -v "$master_data:/bitnami/redis/data" \
    -v "$master_conf:/opt/bitnami/redis/mounted-etc:ro" \
    -e REDIS_REPLICATION_MODE=master -e REDIS_PASSWORD="$master_password" \
    -e REDIS_EXTRA_FLAGS="--requirepass $master_password" "$IMAGE" >/dev/null
containers+=("$master")
docker create --name "$replica" --network "$prefix" \
    -v "$replica_data:/bitnami/redis/data" \
    -e REDIS_REPLICATION_MODE=slave -e REDIS_PASSWORD="$replica_password" \
    -e REDIS_MASTER_HOST="$master" -e REDIS_MASTER_PORT_NUMBER=6380 \
    -e REDIS_MASTER_PASSWORD="$master_password" -e REDIS_EXTRA_FLAGS='--port 6381' "$IMAGE" >/dev/null
containers+=("$replica")
docker start "$master" "$replica" >/dev/null
wait_for PONG master_cli PING
wait_for PONG replica_cli PING
check_logs "$master" master 'Using mounted Redis configuration' 'Applying additional Redis arguments'
check_logs "$replica" slave 'Generating default Redis configuration with AOF enabled' 'Applying replica connection settings' 'Applying additional Redis arguments'

[[ "$(master_cli INFO server | tr -d '\r' | sed -n 's/^redis_version://p')" == "$redis_version" ]]
[[ "$(docker exec "$master" id -u)" == 1001 ]]
[[ "$(docker exec "$replica" id -g)" == 1001 ]]
[[ "$(docker exec "$master" readlink /proc/1/exe)" == /usr/local/bin/redis-server ]]
[[ "$(master_cli CONFIG GET appendonly | tail -n 1)" == no ]]
[[ "$(master_cli CONFIG GET maxmemory | tail -n 1)" == 67108864 ]]
[[ "$(replica_cli CONFIG GET appendonly | tail -n 1)" == yes ]]
[[ "$(replica_cli CONFIG SET appendfsync always)" == OK ]]
[[ "$(master_cli SET counter 0)" == OK ]]
wait_for 0 replica_cli GET counter
[[ "$(replica_cli CLIENT PAUSE 10000 WRITE)" == OK ]]

for value in {1..40}; do
    [[ "$(master_cli INCR counter)" == "$value" ]]
    [[ "$(master_cli SET "entry:$value" "value $value")" == OK ]]
    if [[ "$value" == 1 ]]; then
        [[ "$(replica_cli GET counter)" == 0 ]]
        wait_for 1 replica_cli GET counter
    fi
done
wait_for 40 replica_cli GET counter
wait_for 'value 40' replica_cli GET entry:40
docker exec "$replica" test -s "$aof_file"
[[ "$(replica_cli SET rejected value)" == 'READONLY '* ]]
[[ "$(master_cli SAVE)" == OK ]]

docker kill --signal KILL "$master" >/dev/null
docker start "$master" >/dev/null
wait_for PONG master_cli PING
check_logs "$master" master 'Using mounted Redis configuration'
[[ "$(master_cli GET counter)" == 40 ]]
[[ "$(master_cli GET entry:40)" == 'value 40' ]]

for value in {41..80}; do
    [[ "$(master_cli INCR counter)" == "$value" ]]
    [[ "$(master_cli SET "entry:$value" "value $value")" == OK ]]
    if [[ "$value" == 41 ]]; then
        wait_for 41 replica_cli GET counter
        wait_for 'value 41' replica_cli GET entry:41
    fi
done
wait_for 80 replica_cli GET counter
wait_for 'value 80' replica_cli GET entry:80
[[ "$(master_cli SAVE)" == OK ]]
docker stop --time 10 "$master" >/dev/null
docker kill --signal KILL "$replica" >/dev/null
docker start "$replica" >/dev/null
wait_for PONG replica_cli PING
check_logs "$replica" slave 'Generating default Redis configuration with AOF enabled' 'Applying replica connection settings'
[[ "$(replica_cli GET counter)" == 80 ]]
[[ "$(replica_cli GET entry:80)" == 'value 80' ]]

docker start "$master" >/dev/null
wait_for PONG master_cli PING
check_logs "$master" master 'Using mounted Redis configuration'
[[ "$(master_cli INCR counter)" == 81 ]]
wait_for 81 replica_cli GET counter
check_logs "$master" master 'Using mounted Redis configuration'
check_logs "$replica" slave 'Applying replica connection settings'
printf 'Redis %s replication, configuration, persistence and reconnect checks passed.\n' "$redis_version"
