#!/bin/bash
set -e

cd "${HERMES_HOME:-/opt/data}/workspace"
exec hermes gateway run
