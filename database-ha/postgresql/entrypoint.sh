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

export PGDATA=/bitnami/postgresql/data
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD="${POSTGRESQL_PASSWORD:-}"
export POSTGRES_DB="${POSTGRESQL_DATABASE:-postgres}"
export PGPORT="${POSTGRESQL_PORT_NUMBER:-5432}"
mode="${POSTGRESQL_REPLICATION_MODE:-master}"
conf=/bitnami/postgresql/conf

case "$mode" in
    master|slave) ;;
    *) printf >&2 'POSTGRESQL_REPLICATION_MODE must be master or slave\n'; exit 1 ;;
esac
if [[ ! "$PGPORT" =~ ^[0-9]{1,5}$ ]] || (( 10#$PGPORT < 1 || 10#$PGPORT > 65535 )); then
    printf >&2 'POSTGRESQL_PORT_NUMBER must be between 1 and 65535\n'
    exit 1
fi
export PGPORT="$((10#$PGPORT))"
if [[ -z "${POSTGRESQL_REPLICATION_USER:-}" || -z "${POSTGRESQL_REPLICATION_PASSWORD:-}" ]]; then
    printf >&2 'POSTGRESQL_REPLICATION_USER and POSTGRESQL_REPLICATION_PASSWORD are required\n'
    exit 1
fi
if [[ "$POSTGRESQL_REPLICATION_USER" == postgres ]]; then
    printf >&2 'The replication user must differ from postgres\n'
    exit 1
fi
for value in "$POSTGRESQL_REPLICATION_USER" "$POSTGRESQL_REPLICATION_PASSWORD"; do
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        printf >&2 'Replication user and password must not contain line breaks\n'
        exit 1
    fi
done

mkdir -p "$conf"
docker_setup_env
docker_create_db_directories
if [[ "$(id -u)" == 0 ]]; then
    chown postgres:postgres /bitnami/postgresql
    chown -R postgres:postgres "$conf"
    exec gosu postgres "$0" "$@"
fi
if [[ -s "$PGDATA/PG_VERSION" && "$(< "$PGDATA/PG_VERSION")" != "$PG_MAJOR" ]]; then
    printf >&2 'Existing data requires PostgreSQL %s; this image uses %s\n' "$(< "$PGDATA/PG_VERSION")" "$PG_MAJOR"
    exit 1
fi
if [[ -z "$DATABASE_ALREADY_EXISTS" && -n "$(find "$PGDATA" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    printf >&2 'PGDATA is nonempty without PG_VERSION; refusing to initialize or delete its contents\n'
    exit 1
fi
if [[ "$mode" == slave && -n "$DATABASE_ALREADY_EXISTS" && ! -f "$PGDATA/standby.signal" ]]; then
    printf >&2 'Existing data is not a standby; refusing to change its role\n'
    exit 1
fi

if [[ "$mode" == slave ]]; then
    : "${POSTGRESQL_MASTER_HOST:?POSTGRESQL_MASTER_HOST is required for a slave}"
    master_port="${POSTGRESQL_MASTER_PORT_NUMBER:-5432}"
    if [[ ! "$master_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$master_port < 1 || 10#$master_port > 65535 )); then
        printf >&2 'POSTGRESQL_MASTER_PORT_NUMBER must be between 1 and 65535\n'
        exit 1
    fi
    master_port="$((10#$master_port))"
    if [[ "$POSTGRESQL_MASTER_HOST" == *$'\n'* || "$POSTGRESQL_MASTER_HOST" == *$'\r'* ]]; then
        printf >&2 'Replication host must not contain line breaks\n'
        exit 1
    fi
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
        pg_basebackup --host "$POSTGRESQL_MASTER_HOST" --port "$master_port" \
            --username "$POSTGRESQL_REPLICATION_USER" --pgdata "$clone_dir" \
            --wal-method stream --write-recovery-conf --no-password --no-clean
        rmdir "$PGDATA"
        mv "$clone_dir" "$PGDATA"
        trap - EXIT
    fi
    master_host="${POSTGRESQL_MASTER_HOST//\\/\\\\}"
    master_host="${master_host//\'/\\\'}"
    replication_user="${POSTGRESQL_REPLICATION_USER//\\/\\\\}"
    replication_user="${replication_user//\'/\\\'}"
    set -- "$@" -c "primary_conninfo=host='$master_host' port='$master_port' user='$replication_user' passfile='$PGPASSFILE'"
elif [[ -f "$PGDATA/standby.signal" || -f "$PGDATA/recovery.signal" ]]; then
    printf >&2 'Existing data is in recovery; refusing to change its role\n'
    exit 1
elif [[ -z "$DATABASE_ALREADY_EXISTS" ]]; then
    docker_verify_minimum_env
    docker_init_database_dir --auth-host=scram-sha-256
    printf '\nhost all all all scram-sha-256\n' >> "$PGDATA/pg_hba.conf"
fi

if [[ ! -e "$conf/postgresql.conf" ]]; then
    printf "listen_addresses = '*'\nwal_level = replica\nhot_standby = on\nwal_keep_size = '128MB'\n" > "$conf/postgresql.conf"
fi
if [[ ! -e "$conf/pg_hba.conf" ]]; then
    if [[ -f "$PGDATA/pg_hba.conf" ]]; then
        cp "$PGDATA/pg_hba.conf" "$conf/pg_hba.conf"
    else
        printf 'local all all peer\nhost all all all scram-sha-256\n' > "$conf/pg_hba.conf"
    fi
fi
set -- "$@" -c "config_file=$conf/postgresql.conf" -c "data_directory=$PGDATA" \
    -c "hba_file=$conf/pg_hba.conf" -c "ident_file=$PGDATA/pg_ident.conf" \
    -c unix_socket_directories=/var/run/postgresql -p "$PGPORT"

if [[ "$mode" == master ]]; then
    rule='host replication all all scram-sha-256'
    if ! grep -Fqx "$rule" "$conf/pg_hba.conf"; then
        printf '\n%s\n' "$rule" >> "$conf/pg_hba.conf"
    fi
    docker_temp_server_start "$@"
    trap 'docker_temp_server_stop' EXIT
    PGPASSWORD="$POSTGRES_PASSWORD" docker_process_sql --dbname postgres <<'SQL'
\getenv replication_user POSTGRESQL_REPLICATION_USER
\getenv replication_password POSTGRESQL_REPLICATION_PASSWORD
SELECT format('CREATE ROLE %I WITH LOGIN REPLICATION', :'replication_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'replication_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN REPLICATION PASSWORD %L', :'replication_user', :'replication_password') \gexec
SQL
    if [[ -z "$DATABASE_ALREADY_EXISTS" ]]; then
        docker_setup_db
        docker_process_init_files /docker-entrypoint-initdb.d/*
    fi
    docker_temp_server_stop
    trap - EXIT
fi

exec "$@"
