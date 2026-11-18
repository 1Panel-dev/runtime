#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "${1:0:1}" == '-' ]]; then
    set -- mysqld "$@"
fi
if [[ "$1" != mysqld ]]; then
    exec "$@"
fi
shift

log() {
    local level="$1"
    shift
    printf '%s [%s] MySQL cluster (%s): %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "${role:-startup}" "$*" >&2
}

fail() {
    log ERROR "$*"
    exit 1
}

sql_literal() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"
    printf "'%s'" "$value"
}

mysql_local() {
    MYSQL_PWD="$mysql_password" mysql --defaults-file="$config_file" \
      --protocol=socket --socket="$socket_file" --user=root --batch --skip-column-names "$@"
}

cleanup_init() {
    local result="$1"
    trap - EXIT
    log ERROR "Setup failed with exit code $result; data has been preserved in $data_dir"
    log INFO 'Stopping temporary MySQL server'
    MYSQL_PWD="$mysql_password" mysqladmin --defaults-file="$config_file" --socket="$socket_file" \
      --user=root shutdown >/dev/null 2>&1 || true
    if [[ ! -L "$log_file" && -f "$log_file" ]]; then
        tail -n 100 "$log_file" >&2
    fi
    exit "$result"
}

role="${MYSQL_REPLICATION_MODE:-}"
[[ "$role" == master || "$role" == slave ]] || fail 'MYSQL_REPLICATION_MODE must be master or slave'
log INFO 'Validating replication settings'
[[ -n "${MYSQL_ROOT_PASSWORD:-}" ]] || fail 'MYSQL_ROOT_PASSWORD is required'
[[ -n "${MYSQL_REPLICATION_USER:-}" && -n "${MYSQL_REPLICATION_PASSWORD:-}" ]] || \
    fail 'MYSQL_REPLICATION_USER and MYSQL_REPLICATION_PASSWORD are required'
[[ "$MYSQL_REPLICATION_USER" != root ]] || fail 'MYSQL_REPLICATION_USER cannot be root'

if [[ "$role" == slave ]]; then
    [[ -n "${MYSQL_MASTER_HOST:-}" && -n "${MYSQL_MASTER_ROOT_PASSWORD:-}" ]] || \
        fail 'MYSQL_MASTER_HOST and MYSQL_MASTER_ROOT_PASSWORD are required'
fi

config_file=/opt/bitnami/mysql/conf/my.cnf
data_dir=/bitnami/mysql/data
socket_file=/opt/bitnami/mysql/tmp/mysql.sock
pid_file=/opt/bitnami/mysql/tmp/mysqld.pid
log_file=/opt/bitnami/mysql/logs/mysqld.log
mkdir -p "$data_dir" /opt/bitnami/mysql/tmp /opt/bitnami/mysql/logs
[[ ! -e "$data_dir/.1panel-initializing" ]] || \
    fail 'previous initialization did not finish; inspect the logs and recover this unfinished new node before retrying'
if [[ -f "$data_dir/.1panel-replication-mode" ]]; then
    [[ "$(cat "$data_dir/.1panel-replication-mode")" == "$role" ]] || fail 'data directory belongs to a different replication role'
fi

if [[ -f "$data_dir/.1panel-server-id" ]]; then
    server_id="$(cat "$data_dir/.1panel-server-id")"
elif [[ -f "$data_dir/auto.cnf" ]]; then
    read -r server_id _ < <(cksum "$data_dir/auto.cnf")
else
    server_id="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
fi
[[ "$server_id" =~ ^[0-9]+$ ]] && (( server_id > 0 && server_id <= 4294967295 )) || fail 'invalid server ID'

args=(mysqld "--defaults-file=$config_file" --basedir=/usr --plugin-dir=/usr/lib64/mysql/plugin
      "--datadir=$data_dir" "--socket=$socket_file" "--pid-file=$pid_file" "--log-error=$log_file"
      "--server-id=$server_id" "--log-bin=$data_dir/mysql-bin" "--relay-log=$data_dir/mysql-relay-bin")
plugin="${MYSQL_AUTHENTICATION_PLUGIN:-caching_sha2_password}"
case "$plugin" in
    mysql_native_password) args+=(--mysql-native-password=ON) ;;
    caching_sha2_password) ;;
    *) fail 'MYSQL_AUTHENTICATION_PLUGIN must be mysql_native_password or caching_sha2_password' ;;
esac
if [[ "$role" == slave ]]; then
    args+=(--read-only=ON --super-read-only=ON)
fi
args+=("$@")

mysql_password="$MYSQL_ROOT_PASSWORD"
if [[ "$role" == slave && "${MYSQL_REPLICATION_SLAVE_DUMP:-false}" == true ]]; then
    mysql_password="$MYSQL_MASTER_ROOT_PASSWORD"
fi

if [[ -d "$data_dir/mysql" && ! -f "$data_dir/.1panel-replication-mode" ]]; then
    log INFO 'Checking replication role in existing data'
    trap 'cleanup_init "$?"' EXIT
    log INFO 'Starting temporary MySQL server'
    "${args[@]}" --daemonize --skip-networking --read-only=OFF --super-read-only=OFF --skip-replica-start
    channels="$(mysql_local --execute="SELECT COUNT(*) FROM performance_schema.replication_connection_configuration WHERE HOST<>''")"
    if [[ "$role" == master && "$channels" != 0 || "$role" == slave && "$channels" == 0 ]]; then
        fail 'existing data replication channels do not match MYSQL_REPLICATION_MODE'
    fi
    log INFO 'Stopping temporary MySQL server'
    MYSQL_PWD="$mysql_password" mysqladmin --defaults-file="$config_file" --socket="$socket_file" --user=root shutdown
    printf '%s\n' "$role" > "$data_dir/.1panel-replication-mode"
    trap - EXIT
fi

if [[ ! -d "$data_dir/mysql" ]]; then
    log INFO "Initializing $role database"
    touch "$data_dir/.1panel-initializing"
    mysql_password=''
    trap 'cleanup_init "$?"' EXIT
    "${args[@]}" --initialize-insecure --read-only=OFF --super-read-only=OFF
    log INFO 'Starting temporary MySQL server'
    "${args[@]}" --daemonize --skip-networking --read-only=OFF --super-read-only=OFF --skip-replica-start

    root_password="$MYSQL_ROOT_PASSWORD"
    if [[ "$role" == slave && "${MYSQL_REPLICATION_SLAVE_DUMP:-false}" == true ]]; then
        root_password="$MYSQL_MASTER_ROOT_PASSWORD"
    fi
    log INFO 'Configuring root authentication'
    mysql_local <<SQL
SET SESSION sql_mode='';
SET SESSION sql_log_bin=0;
ALTER USER 'root'@'localhost' IDENTIFIED WITH $plugin BY $(sql_literal "$root_password");
CREATE USER 'root'@'%' IDENTIFIED WITH $plugin BY $(sql_literal "$root_password");
GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;
SQL
    mysql_password="$root_password"

    if [[ "$role" == master ]]; then
        log INFO 'Creating replication account'
        mysql_local <<SQL
SET SESSION sql_mode='';
SET SESSION sql_log_bin=0;
CREATE USER $(sql_literal "$MYSQL_REPLICATION_USER")@'%' IDENTIFIED WITH $plugin BY $(sql_literal "$MYSQL_REPLICATION_PASSWORD");
GRANT REPLICATION SLAVE ON *.* TO $(sql_literal "$MYSQL_REPLICATION_USER")@'%';
SQL
    else
        master_port="${MYSQL_MASTER_PORT_NUMBER:-3306}"
        [[ "$master_port" =~ ^[0-9]+$ ]] && (( master_port > 0 && master_port <= 65535 )) || fail 'invalid MYSQL_MASTER_PORT_NUMBER'
        master_user="${MYSQL_MASTER_ROOT_USER:-root}"
        log INFO "Waiting for master $MYSQL_MASTER_HOST:$master_port"
        ready=false
        wait_started=$SECONDS
        next_wait_log=0
        failure_reason='SQL connection failed'
        for (( attempt=1; attempt<=300; attempt++ )); do
            if connection_error="$(MYSQL_PWD="$MYSQL_MASTER_ROOT_PASSWORD" mysql --no-defaults --protocol=tcp --connect-timeout=5 \
              --host="$MYSQL_MASTER_HOST" --port="$master_port" --user="$master_user" --execute='SELECT 1' 2>&1)"; then
                ready=true
                log INFO "Master connection established after $attempt attempt(s), $((SECONDS - wait_started))s elapsed"
                break
            fi
            case "$connection_error" in
                *'ERROR 1045'*|*'ERROR 1698'*) failure_reason='authentication rejected; verify the master credentials' ;;
                *'ERROR 2005'*) failure_reason='master hostname could not be resolved' ;;
                *'ERROR 2003'*)
                    case "$connection_error" in
                        *'(110)'*|*'timed out'*) failure_reason='connection timed out; verify the master address, port and network access' ;;
                        *'(111)'*|*'Connection refused'*) failure_reason='connection refused; verify the master is listening on this address and port' ;;
                        *) failure_reason='TCP connection to the master failed' ;;
                    esac
                    ;;
                *'ERROR 2026'*) failure_reason='TLS connection failed; verify the master TLS settings' ;;
                *) failure_reason='SQL connection failed' ;;
            esac
            elapsed=$((SECONDS - wait_started))
            if (( elapsed >= next_wait_log || attempt == 300 )); then
                log WARN "Master $MYSQL_MASTER_HOST:$master_port is not ready (attempt $attempt/300, ${elapsed}s elapsed): $failure_reason"
                next_wait_log=$((elapsed + 30))
            fi
            sleep 2
        done
        [[ "$ready" == true ]] || fail "master did not become available at $MYSQL_MASTER_HOST:$master_port after 300 attempts ($((SECONDS - wait_started))s elapsed): $failure_reason"

        coordinates=''
        if [[ "${MYSQL_REPLICATION_SLAVE_DUMP:-false}" == true ]]; then
            dump_file="$data_dir/.1panel-initial-dump.sql"
            log INFO 'Creating initial dump from master'
            MYSQL_PWD="$MYSQL_MASTER_ROOT_PASSWORD" mysqldump --no-defaults --protocol=tcp \
              --host="$MYSQL_MASTER_HOST" --port="$master_port" --user="$master_user" \
              --all-databases --single-transaction --quick --source-data=2 --set-gtid-purged=OFF \
              --routines --events --triggers > "$dump_file"
            log INFO 'Initial dump created'
            read -r source_file source_position < <(sed -n "s/^-- CHANGE REPLICATION SOURCE TO SOURCE_LOG_FILE='\([^']*\)', SOURCE_LOG_POS=\([0-9]*\);$/\1 \2/p" "$dump_file")
            [[ -n "$source_file" && "$source_position" =~ ^[0-9]+$ ]] || fail 'dump did not contain replication coordinates'
            log INFO "Restoring initial dump (source file $source_file, position $source_position)"
            mysql_local < "$dump_file"
            mysql_local --execute='FLUSH PRIVILEGES'
            rm "$dump_file"
            log INFO 'Initial dump restored'
            coordinates="SOURCE_LOG_FILE=$(sql_literal "$source_file"), SOURCE_LOG_POS=$source_position,"
        fi
        log INFO "Configuring replication from $MYSQL_MASTER_HOST:$master_port"
        mysql_local <<SQL
SET SESSION sql_mode='';
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST=$(sql_literal "$MYSQL_MASTER_HOST"), SOURCE_PORT=$master_port,
  SOURCE_USER=$(sql_literal "$MYSQL_REPLICATION_USER"), SOURCE_PASSWORD=$(sql_literal "$MYSQL_REPLICATION_PASSWORD"),
  $coordinates SOURCE_AUTO_POSITION=0, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=10;
START REPLICA;
SQL
        log INFO 'Replication configuration applied'
    fi

    log INFO 'Stopping temporary MySQL server'
    MYSQL_PWD="$mysql_password" mysqladmin --defaults-file="$config_file" \
      --socket="$socket_file" --user=root shutdown
    printf '%s\n' "$server_id" > "$data_dir/.1panel-server-id"
    printf '%s\n' "$role" > "$data_dir/.1panel-replication-mode"
    rm "$data_dir/.1panel-initializing"
    trap - EXIT
    log INFO 'Initialization complete'
else
    log INFO 'Using existing data'
fi

log INFO "Starting MySQL $role with server ID $server_id"
exec "${args[@]}"
