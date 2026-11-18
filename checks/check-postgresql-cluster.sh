#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:-${IMAGE:-1panel/postgresql-cluster:18.7}}"
prefix="1panel-pg-check-$(date +%s)-$$"
network="$prefix-network"
master="$prefix-master"
slave="$prefix-slave"
volumes=("$prefix-master-data" "$prefix-master-conf" "$prefix-slave-data" "$prefix-slave-conf" "$prefix-invalid-data" "$prefix-invalid-conf" "$prefix-failed-data" "$prefix-failed-conf" "$prefix-major-data")
password=$'pg\'"\\:$ secret'
replication_user=$'replica\'"\\:$ user'
replication_password=$'repl\'"\\:$ secret'

cleanup() {
    result=$?
    if (( result != 0 )); then
        docker logs "$master" >&2 || true
        docker logs "$slave" >&2 || true
    fi
    docker rm -fv "$master" "$slave" "$prefix-invalid" "$prefix-failed" "$prefix-role" "$prefix-major" >/dev/null 2>&1 || true
    for volume in "${volumes[@]}"; do
        docker volume rm "$volume" >/dev/null 2>&1 || true
    done
    docker network rm "$network" >/dev/null 2>&1 || true
    exit "$result"
}
trap cleanup EXIT

wait_healthy() {
    container="$1"
    for (( attempt=0; attempt<90; attempt++ )); do
        status="$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container")"
        if [[ "$status" == 'running healthy' ]]; then
            return
        fi
        if [[ "$status" == exited* || "$status" == dead* ]]; then
            printf >&2 '%s stopped before becoming healthy\n' "$container"
            return 1
        fi
        sleep 1
    done
    printf >&2 '%s did not become healthy\n' "$container"
    return 1
}

sql() {
    docker exec "$1" psql -U postgres -d postgres -p "$2" -Atqc "$3"
}

wait_rows() {
    expected="$1"
    for (( attempt=0; attempt<60; attempt++ )); do
        actual="$(sql "$slave" 55433 'SELECT count(*) FROM cluster_probe' 2>/dev/null || true)"
        if [[ "$actual" == "$expected" ]]; then
            return
        fi
        sleep 1
    done
    printf >&2 'Expected %s replicated rows, got %s\n' "$expected" "$actual"
    return 1
}

check_log_secrets() {
    if [[ "$1" == *"$password"* || "$1" == *"$replication_password"* ]]; then
        printf >&2 'PostgreSQL logs exposed a configured password\n'
        return 1
    fi
}

check_startup_logs() {
    local container="$1"
    shift
    local started_at logs message attempt
    started_at="$(docker inspect --format '{{.State.StartedAt}}' "$container")"
    for (( attempt=0; attempt<90; attempt++ )); do
        logs="$(docker logs --since "$started_at" "$container" 2>&1)"
        check_log_secrets "$logs"
        if awk '
            /\[INFO\] PostgreSQL cluster \((master|slave)\): Starting PostgreSQL on port / { started = 1; ready = 0; next }
            started && /database system is ready to accept/ { ready = 1 }
            END { exit !ready }
        ' <<< "$logs"; then
            break
        fi
        sleep 1
    done
    if (( attempt == 90 )); then
        printf >&2 'PostgreSQL engine readiness log is missing after the current startup: %s\n' "$container"
        return 1
    fi
    if ! grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[INFO\] PostgreSQL cluster \((master|slave)\): ' <<< "$logs"; then
        printf >&2 'Structured PostgreSQL startup log is missing: %s\n' "$container"
        return 1
    fi
    for message in "$@"; do
        if ! grep -Fq "$message" <<< "$logs"; then
            printf >&2 'PostgreSQL startup log is missing for %s: %s\n' "$container" "$message"
            return 1
        fi
    done
}

docker image inspect "$image" >/dev/null
major="$(docker run --rm "$image" bash -ec 'printf "%s" "$PG_MAJOR"')"
case "$major" in
    15|16|17|18) ;;
    *) printf >&2 'Unsupported PostgreSQL major: %s\n' "$major"; exit 1 ;;
esac
docker network create "$network" >/dev/null
for volume in "${volumes[@]}"; do
    docker volume create "$volume" >/dev/null
done

docker run --rm --user root \
    -v "${volumes[1]}:/conf" -v "${volumes[3]}:/slave-conf" \
    -v "${volumes[4]}:/invalid" "$image" bash -ec '
        printf "listen_addresses = '\''*'\''\nshared_buffers = '\''32MB'\''\n" > /conf/postgresql.conf
        printf "listen_addresses = '\''*'\''\nshared_buffers = '\''48MB'\''\n" > /slave-conf/postgresql.conf
        mkdir -p /invalid/data
        printf "preserve me\n" > /invalid/data/user-file
        chown -R 1001:1001 /conf /slave-conf /invalid
    '

docker run -d --name "$master" --network "$network" --network-alias pg-master \
    -e POSTGRESQL_REPLICATION_MODE=master -e POSTGRESQL_PORT_NUMBER=55432 \
    -e "POSTGRESQL_PASSWORD=$password" -e "POSTGRESQL_REPLICATION_USER=$replication_user" \
    -e "POSTGRESQL_REPLICATION_PASSWORD=$replication_password" \
    -v "${volumes[0]}:/bitnami/postgresql" -v "${volumes[1]}:/bitnami/postgresql/conf" "$image" >/dev/null
wait_healthy "$master"
check_startup_logs "$master" 'Initializing master database' 'Configuring primary replication account' 'Startup configuration complete'
[[ "$(sql "$master" 55432 'SHOW shared_buffers')" == 32MB ]]
[[ "$(docker exec "$master" id -u)" == 1001 ]]
[[ "$(sql "$master" 55432 "SELECT current_setting('server_version_num')::integer / 10000")" == "$major" ]]
[[ "$(docker exec -e "PGPASSWORD=$password" "$master" psql -h 127.0.0.1 -p 55432 -U postgres -d postgres -Atqc 'SELECT 1')" == 1 ]]
master_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$master")"
[[ "$(docker exec -e "PGPASSWORD=$password" "$master" psql -h "$master_ip" -p 55432 -U postgres -d postgres -Atqc 'SELECT 1')" == 1 ]]
if docker exec -e PGPASSWORD=incorrect "$master" psql -h 127.0.0.1 -p 55432 -U postgres -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1; then
    printf >&2 'Primary unexpectedly accepted an incorrect password\n'
    exit 1
fi
sql "$master" 55432 "CREATE TABLE cluster_probe (id integer PRIMARY KEY, value text); INSERT INTO cluster_probe VALUES (1, 'before-replica');" >/dev/null
master_id="$(sql "$master" 55432 'SELECT system_identifier FROM pg_control_system()')"
docker exec -i "$master" psql -U postgres -d postgres -p 55432 -v ON_ERROR_STOP=1 \
    --set replication_user="$replication_user" >/dev/null <<'SQL'
SELECT format('DROP ROLE %I', :'replication_user') \gexec
SQL
docker exec "$master" bash -ec '
    printf "local all all peer\nhost all all 127.0.0.1/32 scram-sha-256\n" > "$PGDATA/pg_hba.conf"
    rm /bitnami/postgresql/conf/pg_hba.conf
'
docker restart "$master" >/dev/null
wait_healthy "$master"
check_startup_logs "$master" 'Using existing master data; skipping initialization and base backup' 'Configuring primary replication account'
[[ "$(sql "$master" 55432 'SELECT system_identifier FROM pg_control_system()')" == "$master_id" ]]
[[ "$(docker exec -e "PGPASSWORD=$password" "$master" psql -h 127.0.0.1 -p 55432 -U postgres -d postgres -Atqc 'SELECT 1')" == 1 ]]
if docker exec -e "PGPASSWORD=$password" "$master" psql -h "$master_ip" -p 55432 -U postgres -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1; then
    printf >&2 'Primary copied authentication unexpectedly bypassed the IP whitelist\n'
    exit 1
fi

docker run -d --name "$slave" --network "$network" \
    -e POSTGRESQL_REPLICATION_MODE=slave -e POSTGRESQL_PORT_NUMBER=55433 \
    -e POSTGRESQL_MASTER_HOST=pg-master -e POSTGRESQL_MASTER_PORT_NUMBER=55432 \
    -e "POSTGRESQL_PASSWORD=$password" -e "POSTGRESQL_REPLICATION_USER=$replication_user" \
    -e "POSTGRESQL_REPLICATION_PASSWORD=$replication_password" \
    -v "${volumes[2]}:/bitnami/postgresql" -v "${volumes[3]}:/bitnami/postgresql/conf" "$image" >/dev/null
wait_healthy "$slave"
check_startup_logs "$slave" 'Cloning standby database from primary; waiting for base backup' 'Standby base backup complete' 'Configuring standby replication connection'
[[ "$(sql "$slave" 55433 'SELECT pg_is_in_recovery()')" == t ]]
[[ "$(sql "$slave" 55433 'SHOW shared_buffers')" == 48MB ]]
[[ "$(sql "$slave" 55433 'SELECT system_identifier FROM pg_control_system()')" == "$master_id" ]]
docker exec "$slave" cmp /bitnami/postgresql/data/pg_hba.conf /bitnami/postgresql/conf/pg_hba.conf
[[ "$(docker exec -e "PGPASSWORD=$password" "$slave" psql -h 127.0.0.1 -p 55433 -U postgres -d postgres -Atqc 'SELECT 1')" == 1 ]]
slave_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$slave")"
if docker exec -e "PGPASSWORD=$password" "$slave" psql -h "$slave_ip" -p 55433 -U postgres -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1; then
    printf >&2 'Standby copied authentication unexpectedly bypassed the IP whitelist\n'
    exit 1
fi
wait_rows 1
sql "$master" 55432 "INSERT INTO cluster_probe VALUES (2, 'streaming');" >/dev/null
wait_rows 2
[[ "$(sql "$master" 55432 "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'")" == 1 ]]
if sql "$slave" 55433 "INSERT INTO cluster_probe VALUES (3, 'must-fail')" >/dev/null 2>&1; then
    printf >&2 'Standby unexpectedly accepted a write\n'
    exit 1
fi
docker stop "$slave" >/dev/null
sql "$master" 55432 "INSERT INTO cluster_probe VALUES (3, 'offline-replica');" >/dev/null
docker start "$slave" >/dev/null
wait_healthy "$slave"
check_startup_logs "$slave" 'Using existing slave data; skipping initialization and base backup' 'Configuring standby replication connection'
wait_rows 3
docker restart "$master" >/dev/null
wait_healthy "$master"
check_startup_logs "$master" 'Using existing master data; skipping initialization and base backup' 'Configuring primary replication account'
sql "$master" 55432 "INSERT INTO cluster_probe VALUES (4, 'restarted-primary');" >/dev/null
wait_rows 4
[[ "$(docker exec "$slave" stat -c '%u:%g:%a' /bitnami/postgresql/conf/replication.pgpass)" == 1001:1001:600 ]]

if docker run --name "$prefix-invalid" -e POSTGRESQL_REPLICATION_MODE=slave \
    -e POSTGRESQL_MASTER_HOST=unreachable -e "POSTGRESQL_REPLICATION_USER=$replication_user" \
    -e "POSTGRESQL_REPLICATION_PASSWORD=$replication_password" \
    -v "${volumes[4]}:/bitnami/postgresql" -v "${volumes[5]}:/bitnami/postgresql/conf" "$image" >/dev/null 2>&1; then
    printf >&2 'Nonempty unrecognized data directory was unexpectedly accepted\n'
    exit 1
fi
[[ "$(docker run --rm -v "${volumes[4]}:/bitnami/postgresql" "$image" cat /bitnami/postgresql/data/user-file)" == 'preserve me' ]]

docker run --rm --user root -v "${volumes[7]}:/conf" "$image" bash -ec '
    printf "preserve configuration\n" > /conf/user-file
    chown -R 1001:1001 /conf
'
if docker run --name "$prefix-failed" --network "$network" \
    -e POSTGRESQL_REPLICATION_MODE=slave -e POSTGRESQL_MASTER_HOST=pg-master \
    -e POSTGRESQL_MASTER_PORT_NUMBER=1 -e "POSTGRESQL_REPLICATION_USER=$replication_user" \
    -e "POSTGRESQL_REPLICATION_PASSWORD=$replication_password" \
    -v "${volumes[6]}:/bitnami/postgresql" -v "${volumes[7]}:/bitnami/postgresql/conf" "$image" >/dev/null 2>&1; then
    printf >&2 'Clone unexpectedly succeeded against a closed port\n'
    exit 1
fi
failed_started_at="$(docker inspect --format '{{.State.StartedAt}}' "$prefix-failed")"
failed_logs="$(docker logs --since "$failed_started_at" "$prefix-failed" 2>&1)"
check_log_secrets "$failed_logs"
grep -Fq '[ERROR] PostgreSQL cluster (slave): Standby base backup failed' <<< "$failed_logs"
[[ "$(docker run --rm -v "${volumes[7]}:/conf" "$image" cat /conf/user-file)" == 'preserve configuration' ]]
[[ -z "$(docker run --rm -v "${volumes[6]}:/bitnami/postgresql" "$image" find /bitnami/postgresql -maxdepth 1 -name '.clone.*' -print)" ]]

docker stop "$master" >/dev/null
if docker run --name "$prefix-role" -e POSTGRESQL_REPLICATION_MODE=slave \
    -e POSTGRESQL_MASTER_HOST=pg-master -e "POSTGRESQL_REPLICATION_USER=$replication_user" \
    -e "POSTGRESQL_REPLICATION_PASSWORD=$replication_password" \
    -v "${volumes[0]}:/bitnami/postgresql" -v "${volumes[1]}:/bitnami/postgresql/conf" "$image" >/dev/null 2>&1; then
    printf >&2 'Existing primary was unexpectedly changed into a standby\n'
    exit 1
fi
[[ "$(docker run --rm -v "${volumes[0]}:/bitnami/postgresql" "$image" cat /bitnami/postgresql/data/PG_VERSION)" == "$major" ]]
docker start "$master" >/dev/null
wait_healthy "$master"
check_startup_logs "$master" 'Using existing master data; skipping initialization and base backup'
[[ "$(sql "$master" 55432 'SELECT system_identifier FROM pg_control_system()')" == "$master_id" ]]
[[ "$(sql "$master" 55432 'SELECT count(*) FROM cluster_probe')" == 4 ]]

docker stop "$master" >/dev/null
docker rm -v "$master" >/dev/null
docker run --rm --user root -v "${volumes[0]}:/bitnami/postgresql" \
    -v "${volumes[1]}:/bitnami/postgresql/conf" "$image" bash -ec '
        rm -f /bitnami/postgresql/data/pg_hba.conf /bitnami/postgresql/conf/pg_hba.conf
        chown root:root /bitnami/postgresql
        chmod 700 /bitnami/postgresql
    '
docker run -d --user root --name "$master" --network "$network" --network-alias pg-master \
    -e POSTGRESQL_REPLICATION_MODE=master -e POSTGRESQL_PORT_NUMBER=55432 \
    -e "POSTGRESQL_PASSWORD=$password" -e "POSTGRESQL_REPLICATION_USER=$replication_user" \
    -e "POSTGRESQL_REPLICATION_PASSWORD=$replication_password" \
    -v "${volumes[0]}:/bitnami/postgresql" -v "${volumes[1]}:/bitnami/postgresql/conf" "$image" >/dev/null
wait_healthy "$master"
check_startup_logs "$master" 'Preparing directory permissions and switching to the postgres user' 'Using existing master data; skipping initialization and base backup' '[WARN] PostgreSQL cluster (master): Authentication configuration is missing'
[[ "$(docker exec "$master" stat -c '%u:%g' /bitnami/postgresql)" == 1001:1001 ]]
[[ "$(docker exec "$master" stat -c '%u' /proc/1)" == 1001 ]]
[[ "$(docker exec "$master" grep -Fxc 'local all all peer' /bitnami/postgresql/conf/pg_hba.conf)" == 1 ]]
[[ "$(docker exec -e "PGPASSWORD=$password" "$master" psql -h 127.0.0.1 -p 55432 -U postgres -d postgres -Atqc 'SELECT count(*) FROM cluster_probe')" == 4 ]]
master_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$master")"
[[ "$(docker exec -e "PGPASSWORD=$password" "$master" psql -h "$master_ip" -p 55432 -U postgres -d postgres -Atqc 'SELECT count(*) FROM cluster_probe')" == 4 ]]
if docker exec -e PGPASSWORD=incorrect "$master" psql -h 127.0.0.1 -p 55432 -U postgres -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1; then
    printf >&2 'Recovered primary unexpectedly accepted an incorrect password\n'
    exit 1
fi
docker exec --user 1001 "$master" psql -U postgres -d postgres -p 55432 -Atqc "INSERT INTO cluster_probe VALUES (5, 'restored-authentication');" >/dev/null
wait_rows 5

other_major="$((major + 1))"
docker run --rm --user root -v "${volumes[8]}:/bitnami/postgresql" "$image" bash -ec '
    mkdir -p /bitnami/postgresql/data
    printf "%s\n" "$1" > /bitnami/postgresql/data/PG_VERSION
    printf "preserve other major\n" > /bitnami/postgresql/data/user-file
    chown -R 1001:1001 /bitnami/postgresql
' -- "$other_major"
if docker run --name "$prefix-major" -e POSTGRESQL_REPLICATION_MODE=master \
    -e "POSTGRESQL_PASSWORD=$password" -e "POSTGRESQL_REPLICATION_USER=$replication_user" \
    -e "POSTGRESQL_REPLICATION_PASSWORD=$replication_password" \
    -v "${volumes[8]}:/bitnami/postgresql" "$image" >/dev/null 2>&1; then
    printf >&2 'Data from another PostgreSQL major was unexpectedly accepted\n'
    exit 1
fi
docker logs "$prefix-major" 2>&1 | grep -F "Existing data requires PostgreSQL $other_major; this image uses $major" >/dev/null
[[ "$(docker run --rm -v "${volumes[8]}:/bitnami/postgresql" "$image" cat /bitnami/postgresql/data/PG_VERSION)" == "$other_major" ]]
[[ "$(docker run --rm -v "${volumes[8]}:/bitnami/postgresql" "$image" cat /bitnami/postgresql/data/user-file)" == 'preserve other major' ]]

printf 'PostgreSQL primary/replica checks passed for %s\n' "$image"
