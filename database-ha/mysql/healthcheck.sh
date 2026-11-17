#!/usr/bin/env bash
set -euo pipefail

[[ ! -e /bitnami/mysql/data/.1panel-initializing ]]
password="${MYSQL_ROOT_PASSWORD:-}"
if [[ "${MYSQL_REPLICATION_MODE:-}" == slave && "${MYSQL_REPLICATION_SLAVE_DUMP:-false}" == true ]]; then
    password="${MYSQL_MASTER_ROOT_PASSWORD:-$password}"
fi
MYSQL_PWD="$password" exec mysql --defaults-file=/opt/bitnami/mysql/conf/my.cnf \
  --protocol=socket --socket=/opt/bitnami/mysql/tmp/mysql.sock --user=root --execute='SELECT 1' >/dev/null
