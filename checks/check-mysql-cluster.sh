#!/usr/bin/env bash
set -euo pipefail

image="${1:-${IMAGE:-}}"
[[ -n "$image" ]] || { echo 'Usage: check-mysql-cluster.sh IMAGE' >&2; exit 1; }
test_dir="$(mktemp -d)"
prefix="runtime-mysql-$$-$RANDOM"
network="$prefix-network"
master="$prefix-master"
replica="$prefix-replica"
master_volume="$prefix-master-data"
replica_volume="$prefix-replica-data"
root_password="Root'q\\secret!42"
replication_password="Replica'q\\secret!42"

cleanup() {
    result=$?
    if (( result != 0 )); then
        docker logs "$master" >&2 || true
        docker logs "$replica" >&2 || true
    fi
    docker rm -fv "$replica" "$master" >/dev/null 2>&1 || true
    docker volume rm "$replica_volume" "$master_volume" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
    rm -rf "$test_dir"
    exit "$result"
}
trap cleanup EXIT

query() {
    docker exec -e MYSQL_PWD="$root_password" "$1" mysql \
      --user=root --batch --skip-column-names --execute="$2"
}

wait_healthy() {
    local container="$1"
    for (( attempt=0; attempt<180; attempt++ )); do
        if docker exec "$container" /opt/bitnami/scripts/mysql/healthcheck.sh >/dev/null 2>&1; then
            return
        fi
        [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]] || return 1
        sleep 1
    done
    echo "Health check timed out: $container" >&2
    return 1
}

wait_count() {
    local expected="$1"
    for (( attempt=0; attempt<120; attempt++ )); do
        if [[ "$(query "$replica" 'SELECT COUNT(*) FROM ha_test.records' 2>/dev/null || true)" == "$expected" ]]; then
            return
        fi
        sleep 1
    done
    query "$replica" 'SHOW REPLICA STATUS\G' >&2 || true
    return 1
}

check_logs() {
    local container="$1" role="$2" phase="$3"
    shift 3
    local log_file="$test_dir/$role-$phase.log" message started_at missing='required MySQL startup logs'
    started_at="$(docker inspect --format '{{.State.StartedAt}}' "$container")"
    local deadline=$((SECONDS + 60))
    while (( SECONDS < deadline )); do
        docker logs --since "$started_at" "$container" > "$log_file" 2>&1
        missing=''
        for message in "$@"; do
            if ! grep -Fq -- "[INFO] MySQL cluster ($role): $message" "$log_file"; then
                missing="$message"
                break
            fi
        done
        if [[ -z "$missing" ]] && ! grep -Eq "\\[INFO\\] MySQL cluster \\($role\\): Starting MySQL $role with server ID [0-9]+" "$log_file"; then
            missing='MySQL startup stage'
        fi
        if [[ -z "$missing" ]] && ! grep -Eq '\[MY-010931\].*ready for connections.*port: 3306([[:space:]]|$)' "$log_file"; then
            missing='MySQL engine readiness on port 3306'
        fi
        [[ -n "$missing" ]] || return 0
        sleep 1
    done
    echo "Log check timed out after 60s: $container ($phase), waiting for $missing" >&2
    return 1
}

run_replica() {
    docker run -d --name "$replica" --network "$network" \
      -e MYSQL_REPLICATION_MODE=slave -e MYSQL_REPLICATION_USER=replicator \
      -e MYSQL_REPLICATION_PASSWORD="$replication_password" -e MYSQL_ROOT_PASSWORD=unused-on-dump-replica \
      -e MYSQL_MASTER_HOST="$master" -e MYSQL_MASTER_ROOT_PASSWORD="$root_password" \
      -e MYSQL_REPLICATION_SLAVE_DUMP=true -e MYSQL_AUTHENTICATION_PLUGIN=mysql_native_password \
      -v "$replica_volume:/bitnami/mysql/data" \
      -v "$test_dir/my.cnf:/opt/bitnami/mysql/conf/my.cnf:ro" "$image" >/dev/null
}

cat > "$test_dir/my.cnf" <<'EOF'
[mysqld]
basedir=/opt/bitnami/mysql
plugin_dir=/opt/bitnami/mysql/lib/plugin
port=3306
bind_address=0.0.0.0
tmpdir=/opt/bitnami/mysql/tmp
socket=/opt/bitnami/mysql/tmp/mysql.sock
pid_file=/opt/bitnami/mysql/tmp/mysqld.pid
log_error=/opt/bitnami/mysql/logs/mysqld.log
datadir=/bitnami/mysql/data
[client]
socket=/opt/bitnami/mysql/tmp/mysql.sock
plugin_dir=/opt/bitnami/mysql/lib/plugin
EOF
chmod 0755 "$test_dir"
chmod 0644 "$test_dir/my.cnf"
docker network create "$network" >/dev/null
docker volume create "$master_volume" >/dev/null
docker volume create "$replica_volume" >/dev/null
docker run -d --name "$master" --network "$network" \
  -e MYSQL_REPLICATION_MODE=master -e MYSQL_REPLICATION_USER=replicator \
  -e MYSQL_REPLICATION_PASSWORD="$replication_password" -e MYSQL_ROOT_PASSWORD="$root_password" \
  -e MYSQL_AUTHENTICATION_PLUGIN=mysql_native_password \
  -v "$master_volume:/bitnami/mysql/data" \
  -v "$test_dir/my.cnf:/opt/bitnami/mysql/conf/my.cnf" "$image" >/dev/null
wait_healthy "$master"
check_logs "$master" master initial \
  'Configuring root authentication' 'Creating replication account' 'Initialization complete'
[[ "$(docker exec "$master" id -u)" == 1001 ]]
docker exec -e MYSQL_PWD="$root_password" "$master" mysqladmin --user=root ping >/dev/null
[[ "$(query "$master" "SELECT plugin FROM mysql.user WHERE User='root' AND Host='localhost'")" == mysql_native_password ]]
query "$master" "CREATE DATABASE ha_test; CREATE TABLE ha_test.records (id INT PRIMARY KEY, content VARCHAR(80)); INSERT INTO ha_test.records VALUES (1,'before replica'),(2,'existing data'),(3,'snapshot');" >/dev/null
docker exec -e MYSQL_PWD="$root_password" "$master" mysqldump --user=root \
  --single-transaction --routines ha_test > "$test_dir/backup.sql"
query "$master" 'CREATE DATABASE ha_restore' >/dev/null
docker exec -i -e MYSQL_PWD="$root_password" "$master" mysql --user=root ha_restore < "$test_dir/backup.sql"
[[ "$(query "$master" 'SELECT COUNT(*) FROM ha_restore.records')" == 3 ]]

run_replica
wait_healthy "$replica"
wait_count 3
check_logs "$replica" slave initial \
  'Configuring root authentication' "Waiting for master $master:3306" 'Master connection established' \
  'Creating initial dump from master' 'Restoring initial dump' "Configuring replication from $master:3306" \
  'Replication configuration applied' 'Initialization complete'
[[ "$(query "$replica" 'SELECT content FROM ha_test.records WHERE id=2')" == 'existing data' ]]
[[ "$(query "$replica" 'SELECT @@super_read_only')" == 1 ]]
if query "$replica" "INSERT INTO ha_test.records VALUES (99,'must fail')" >/dev/null 2>&1; then
    echo 'Replica unexpectedly accepted a write' >&2
    exit 1
fi
query "$master" "INSERT INTO ha_test.records VALUES (4,'incremental');" >/dev/null
wait_count 4
server_id="$(query "$replica" 'SELECT @@server_id')"
docker exec "$replica" rm /bitnami/mysql/data/.1panel-replication-mode
docker stop "$replica" >/dev/null
query "$master" "INSERT INTO ha_test.records VALUES (5,'while replica stopped');" >/dev/null
docker rm -v "$replica" >/dev/null
run_replica
wait_healthy "$replica"
wait_count 5
check_logs "$replica" slave persisted 'Using existing data'
[[ "$(query "$replica" 'SELECT @@server_id')" == "$server_id" ]]
if docker run --rm -e MYSQL_REPLICATION_MODE=slave -e MYSQL_REPLICATION_USER=replicator \
  -e MYSQL_REPLICATION_PASSWORD="$replication_password" -e MYSQL_ROOT_PASSWORD="$root_password" \
  -e MYSQL_MASTER_HOST="$master" -e MYSQL_MASTER_ROOT_PASSWORD="$root_password" \
  -v "$master_volume:/bitnami/mysql/data" "$image" > "$test_dir/wrong-role.log" 2>&1; then
    echo 'Existing master data unexpectedly accepted slave mode' >&2
    exit 1
fi
grep -q 'different replication role' "$test_dir/wrong-role.log"
docker exec "$master" rm /bitnami/mysql/data/.1panel-replication-mode
docker restart "$master" >/dev/null
wait_healthy "$master"
check_logs "$master" master persisted 'Using existing data'
query "$master" "INSERT INTO ha_test.records VALUES (6,'after master restart');" >/dev/null
wait_count 6
[[ "$(query "$replica" "SELECT COUNT(*) FROM performance_schema.replication_applier_status WHERE SERVICE_STATE='ON'")" == 1 ]]
[[ "$(query "$replica" "SELECT COUNT(*) FROM performance_schema.replication_connection_status WHERE SERVICE_STATE='ON'")" == 1 ]]
docker exec -e MYSQL_PWD="$root_password" "$replica" mysql --user=root \
  --execute='SHOW REPLICA STATUS\G' > "$test_dir/replica-status.log"
grep -Eq '^[[:space:]]*Replica_SQL_Running: Yes$' "$test_dir/replica-status.log"
grep -Eq '^[[:space:]]*Replica_IO_Running: Yes$' "$test_dir/replica-status.log"
if docker run --rm -e MYSQL_REPLICATION_MODE=master -e MYSQL_REPLICATION_USER=replicator \
  -e MYSQL_REPLICATION_PASSWORD="$replication_password" -e MYSQL_ROOT_PASSWORD="$root_password" \
  "$image" bash -c 'touch /bitnami/mysql/data/.1panel-initializing; exec /usr/local/bin/1panel-mysql-entrypoint mysqld' \
  > "$test_dir/unfinished-init.log" 2>&1; then
    echo 'Incomplete initialization unexpectedly accepted' >&2
    exit 1
fi
grep -q 'previous initialization did not finish' "$test_dir/unfinished-init.log"
for log_file in "$test_dir/"*.log; do
    for password in "$root_password" "$replication_password" unused-on-dump-replica; do
        escaped_password="${password//\\/\\\\}"
        escaped_password="$(printf '%s' "$escaped_password" | sed "s/'/''/g")"
        if grep -Fq -- "$password" "$log_file" || grep -Fq -- "$escaped_password" "$log_file"; then
            echo "Configured password found in container output: $(basename "$log_file")" >&2
            exit 1
        fi
    done
done
echo "MySQL cluster runtime checks passed: $image"
