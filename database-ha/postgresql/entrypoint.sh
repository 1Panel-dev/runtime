#!/usr/bin/env bash
set -Eeo pipefail

if [[ "${1:-}" != postgres && "${1:-}" != -* ]]; then
    exec "$@"
fi
if [[ "${1:-}" == -* ]]; then
    set -- postgres "$@"
fi

source /usr/local/bin/docker-entrypoint.sh
if _pg_want_help "$@"; then
    exec "$@"
fi

log() {
    local level="$1"
    shift
    printf '%s [%s] PostgreSQL cluster (%s): %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "${mode:-startup}" "$*" >&2
}

fail() {
    log ERROR "$*"
    exit 1
}

export PGDATA=/bitnami/postgresql/data
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD="${POSTGRESQL_PASSWORD:-}"
export POSTGRES_DB="${POSTGRESQL_DATABASE:-postgres}"
export PGPORT="${POSTGRESQL_PORT_NUMBER:-5432}"
mode="${POSTGRESQL_REPLICATION_MODE:-master}"
conf=/bitnami/postgresql/conf

case "$mode" in
    master|slave) ;;
    *) fail 'POSTGRESQL_REPLICATION_MODE must be master or slave' ;;
esac
log INFO 'Validating replication settings'
if [[ ! "$PGPORT" =~ ^[0-9]{1,5}$ ]] || (( 10#$PGPORT < 1 || 10#$PGPORT > 65535 )); then
    fail 'POSTGRESQL_PORT_NUMBER must be between 1 and 65535'
fi
export PGPORT="$((10#$PGPORT))"
if [[ -z "${POSTGRESQL_REPLICATION_USER:-}" || -z "${POSTGRESQL_REPLICATION_PASSWORD:-}" ]]; then
    fail 'POSTGRESQL_REPLICATION_USER and POSTGRESQL_REPLICATION_PASSWORD are required'
fi
if [[ "$POSTGRESQL_REPLICATION_USER" == postgres ]]; then
    fail 'The replication user must differ from postgres'
fi
for value in "$POSTGRESQL_REPLICATION_USER" "$POSTGRESQL_REPLICATION_PASSWORD"; do
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        fail 'Replication user and password must not contain line breaks'
    fi
done

trap 'log ERROR "Startup failed with exit code $?; check preceding PostgreSQL messages"' ERR
mkdir -p "$conf"
docker_setup_env
docker_create_db_directories
if [[ "$(id -u)" == 0 ]]; then
    log INFO 'Preparing directory permissions and switching to the postgres user'
    chown postgres:postgres /bitnami/postgresql
    chown -R postgres:postgres "$conf"
    exec gosu postgres "$0" "$@"
fi
if [[ -s "$PGDATA/PG_VERSION" && "$(< "$PGDATA/PG_VERSION")" != "$PG_MAJOR" ]]; then
    fail "Existing data requires PostgreSQL $(< "$PGDATA/PG_VERSION"); this image uses $PG_MAJOR"
fi
if [[ -z "$DATABASE_ALREADY_EXISTS" && -n "$(find "$PGDATA" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    fail 'PGDATA is nonempty without PG_VERSION; refusing to initialize or delete its contents'
fi
if [[ "$mode" == slave && -n "$DATABASE_ALREADY_EXISTS" && ! -f "$PGDATA/standby.signal" ]]; then
    fail 'Existing data is not a standby; refusing to change its role'
fi
if [[ -n "$DATABASE_ALREADY_EXISTS" ]]; then
    log INFO "Using existing $mode data; skipping initialization and base backup"
fi

if [[ "$mode" == slave ]]; then
    [[ -n "${POSTGRESQL_MASTER_HOST:-}" ]] || fail 'POSTGRESQL_MASTER_HOST is required for a slave'
    master_port="${POSTGRESQL_MASTER_PORT_NUMBER:-5432}"
    if [[ ! "$master_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$master_port < 1 || 10#$master_port > 65535 )); then
        fail 'POSTGRESQL_MASTER_PORT_NUMBER must be between 1 and 65535'
    fi
    master_port="$((10#$master_port))"
    if [[ "$POSTGRESQL_MASTER_HOST" == *$'\n'* || "$POSTGRESQL_MASTER_HOST" == *$'\r'* ]]; then
        fail 'Replication host must not contain line breaks'
    fi
    log INFO 'Preparing standby replication credentials'
    export PGPASSFILE="$conf/replication.pgpass"
    umask 077
    credentials=()
    for value in "$POSTGRESQL_MASTER_HOST" "$master_port" replication "$POSTGRESQL_REPLICATION_USER" "$POSTGRESQL_REPLICATION_PASSWORD"; do
        value="${value//\\/\\\\}"
        credentials+=( "${value//:/\\:}" )
    done
    (IFS=:; printf '%s\n' "${credentials[*]}") > "$PGPASSFILE"
    chmod 600 "$PGPASSFILE"
    unset credentials
    if [[ -z "$DATABASE_ALREADY_EXISTS" ]]; then
        clone_dir="$(mktemp -d /bitnami/postgresql/.clone.XXXXXX)"
        trap 'rm -rf -- "$clone_dir"' EXIT
        log INFO 'Cloning standby database from primary; waiting for base backup'
        if ! pg_basebackup --host "$POSTGRESQL_MASTER_HOST" --port "$master_port" \
            --username "$POSTGRESQL_REPLICATION_USER" --pgdata "$clone_dir" \
            --wal-method stream --write-recovery-conf --no-password --no-clean --verbose; then
            fail 'Standby base backup failed; temporary clone will be removed and existing data preserved'
        fi
        rmdir "$PGDATA"
        mv "$clone_dir" "$PGDATA"
        trap - EXIT
        log INFO 'Standby base backup complete'
    fi
    log INFO 'Configuring standby replication connection'
    master_host="${POSTGRESQL_MASTER_HOST//\\/\\\\}"
    master_host="${master_host//\'/\\\'}"
    replication_user="${POSTGRESQL_REPLICATION_USER//\\/\\\\}"
    replication_user="${replication_user//\'/\\\'}"
    set -- "$@" -c "primary_conninfo=host='$master_host' port='$master_port' user='$replication_user' passfile='$PGPASSFILE'"
elif [[ -f "$PGDATA/standby.signal" || -f "$PGDATA/recovery.signal" ]]; then
    fail 'Existing data is in recovery; refusing to change its role'
elif [[ -z "$DATABASE_ALREADY_EXISTS" ]]; then
    log INFO 'Initializing master database'
    docker_verify_minimum_env
    docker_init_database_dir --auth-host=scram-sha-256
    printf '\nhost all all all scram-sha-256\n' >> "$PGDATA/pg_hba.conf"
fi

if [[ ! -e "$conf/postgresql.conf" ]]; then
    log INFO 'Creating default PostgreSQL configuration'
    printf "listen_addresses = '*'\nwal_level = replica\nhot_standby = on\nwal_keep_size = '128MB'\n" > "$conf/postgresql.conf"
else
    log INFO 'Using existing PostgreSQL configuration'
fi
if [[ ! -e "$conf/pg_hba.conf" ]]; then
    if [[ -f "$PGDATA/pg_hba.conf" ]]; then
        log INFO 'Copying existing database authentication configuration'
        cp "$PGDATA/pg_hba.conf" "$conf/pg_hba.conf"
    else
        log WARN 'Authentication configuration is missing; creating default peer and SCRAM rules'
        printf 'local all all peer\nhost all all all scram-sha-256\n' > "$conf/pg_hba.conf"
    fi
else
    log INFO 'Using existing authentication configuration'
fi
set -- "$@" -c "config_file=$conf/postgresql.conf" -c "data_directory=$PGDATA" \
    -c "hba_file=$conf/pg_hba.conf" -c "ident_file=$PGDATA/pg_ident.conf" \
    -c unix_socket_directories=/var/run/postgresql -p "$PGPORT"

if [[ "$mode" == master ]]; then
    rule='host replication all all scram-sha-256'
    if ! grep -Fqx "$rule" "$conf/pg_hba.conf"; then
        log INFO 'Adding primary replication authentication rule'
        printf '\n%s\n' "$rule" >> "$conf/pg_hba.conf"
    fi
    log INFO 'Starting temporary PostgreSQL server'
    docker_temp_server_start "$@"
    trap 'log INFO "Stopping temporary PostgreSQL server"; docker_temp_server_stop' EXIT
    log INFO 'Configuring primary replication account'
    PGPASSWORD="$POSTGRES_PASSWORD" docker_process_sql --dbname postgres <<'SQL'
\getenv replication_user POSTGRESQL_REPLICATION_USER
\getenv replication_password POSTGRESQL_REPLICATION_PASSWORD
SELECT format('CREATE ROLE %I WITH LOGIN REPLICATION', :'replication_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'replication_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN REPLICATION PASSWORD %L', :'replication_user', :'replication_password') \gexec
SQL
    if [[ -z "$DATABASE_ALREADY_EXISTS" ]]; then
        log INFO 'Initializing databases and running initialization scripts'
        docker_setup_db
        docker_process_init_files /docker-entrypoint-initdb.d/*
    fi
    log INFO 'Stopping temporary PostgreSQL server'
    docker_temp_server_stop
    trap - EXIT
fi

log INFO 'Startup configuration complete; replication health must be checked separately'
log INFO "Starting PostgreSQL on port $PGPORT"
exec "$@"
