#!/usr/bin/env bash
set -Eeuo pipefail

exec pg_isready -h 127.0.0.1 -p "${POSTGRESQL_PORT_NUMBER:-5432}" -q -U postgres
